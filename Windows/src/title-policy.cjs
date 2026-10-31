"use strict";
const fs = require("node:fs"),
  { Unzip, UnzipInflate } = require("fflate"),
  { SaxesParser } = require("saxes");
const STOP = Symbol("opening-complete");
function whitespace(value) {
  return String(value)
    .replace(/(?<=\p{Script=Han})\s*\r?\n\s*(?=\p{Script=Han})/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}
function cleanTitle(value) {
  return whitespace(value)
    .replace(/[/\\:：*?"<>|\x00-\x1f\x7f]/g, "-")
    .replace(/^[.\s]+|[.\s]+$/g, "");
}
const generic = new Set([
  "目录",
  "目 录",
  "正文",
  "封面",
  "技术方案",
  "招标文件",
  "投标文件",
  "响应文件",
  "应答文件",
  "商务部分",
  "技术部分",
  "方案",
  "项目名称",
  "采购人",
  "供应商",
  "序号",
  "名称",
  "单位",
  "数量",
  "单价",
  "金额",
  "日期",
  "备注",
  "合计",
  "总计",
  "单位名称",
]);
function usableTitle(raw) {
  const s = cleanTitle(raw),
    length = [...s].length;
  return (
    length >= 2 &&
    length <= 160 &&
    !generic.has(s) &&
    !/^[0-9年月日\s./_-]+$/.test(s) &&
    !/^(?:第[一二三四五六七八九十0-9]+[章节条]|项目编号|采购编号|招标编号|法定代表人|编制单位|编制日期|联系人|联系电话|根据|本项目|本文件|本承诺书|本方案)|^(?:单位名称|采购人|供应商|投标人|日期|地址|邮编)[：:]/.test(
      s,
    )
  );
}
function looksLikeTitle(s) {
  if (!usableTitle(s) || [...s].length < 4 || /[。；，]/.test(s)) return false;
  if (
    /(?:方案|报告|计划|规划|清单|明细|汇总|统计|报价|预算|合同|协议|通知|公告|函|承诺书|说明书|手册|规范|标准|要求|指南|记录|试卷|论文|设计|分析|总结|纪要|申请书|申请表|台账|表|建议书|项目|工程|大事记)$/.test(
      s,
    )
  )
    return true;
  const words = s.split(" ").filter((w) => /\p{L}/u.test(w));
  return (
    words.length >= 2 &&
    words.length <= 12 &&
    words.every(
      (w) =>
        ["of", "and", "the", "for", "to", "in"].includes(w.toLowerCase()) ||
        /^\p{Lu}/u.test(w),
    )
  );
}
function textPages(text) {
  return text
    .split("\f")
    .slice(0, 2)
    .map((page, index) => ({
      index,
      lines: page
        .split(/\r?\n/)
        .map((s) => s.trim())
        .filter(Boolean)
        .slice(0, 40)
        .map((text) => ({ text })),
    }));
}
function titleSuggestions(pages, source = "") {
  const titleLabels = [
      "文件名称",
      "文件标题",
      "文档标题",
      "标题",
      "方案名称",
      "报告名称",
      "合同名称",
      "协议名称",
      "表名",
      "报表名称",
      "论文题目",
      "题目",
    ],
    projectLabels = [
      "项目名称",
      "工程名称",
      "采购项目名称",
      "招标项目名称",
      "项目全称",
    ];
  let ranked = [];
  for (const page of pages.slice(0, 2)) {
    const lines = page.lines;
    for (const [index, line] of lines.slice(0, 40).entries()) {
      const raw = line.text.trim(),
        label = page.index === 0 ? "首页" : "第2页";
      let explicit = false;
      for (const field of [...titleLabels, ...projectLabels]) {
        const pattern = new RegExp(
            "^" + [...field].join("\\s*") + "\\s*[：:]\\s*",
          ),
          m = raw.match(pattern);
        if (!m && raw.replace(/ /g, "") !== field) continue;
        explicit = true;
        let value = m ? raw.slice(m[0].length) : "";
        if (!value) value = lines[index + 1]?.text || "";
        if (usableTitle(value))
          ranked.push({
            name: cleanTitle(value),
            evidence: label + "明确标题 · " + source,
            score: page.index * 100 + (projectLabels.includes(field) ? 20 : 0),
          });
      }
      const text = raw.replace(/^#{1,6}\s+/, ""),
        metadata = /[：:]/.test(text);
      if (
        !explicit &&
        usableTitle(text) &&
        !/(有限公司|委员会)$/.test(text) &&
        (line.prominent || (!metadata && looksLikeTitle(text)))
      )
        ranked.push({
          name: cleanTitle(text),
          evidence: label + "标题 · " + source,
          score:
            page.index * 100 + (line.prominent ? 5 : 10) + Math.min(index, 8),
        });
      if (line.joinsNext && !metadata) {
        let joined = text,
          j = index + 1;
        while (
          j < Math.min(lines.length, index + 4) &&
          lines[j - 1].joinsNext
        ) {
          const next = lines[j].text;
          if (/[：:。]/.test(next) || joined.includes("。")) break;
          joined +=
            (/\p{ASCII}$/u.test(joined) && /^\p{ASCII}/u.test(next)
              ? " "
              : "") + next;
          j++;
        }
        if (j > index + 1 && usableTitle(joined))
          ranked.push({
            name: cleanTitle(joined),
            evidence: label + "连续标题 · " + source,
            score: page.index * 100 + 1 + Math.min(index, 30),
          });
      }
    }
  }
  const seen = new Set();
  return ranked
    .sort((a, b) => a.score - b.score)
    .filter((c) => {
      const key = c.name.normalize("NFKC").toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 8);
}
// Inflate only the requested member, feeding bounded text to its consumer. Never extract to disk.
async function zipMember(file, name, consume, signal) {
  signal?.throwIfAborted();
  let found = false,
    done = false,
    failure;
  const unzip = new Unzip((member) => {
    if (member.name !== name) return;
    found = true;
    member.ondata = (err, data, final) => {
      if (done) return;
      if (err) {
        failure = err;
        done = true;
        return;
      }
      try {
        if (consume(data, final) === false || final) {
          done = true;
          member.terminate();
        }
      } catch (e) {
        if (e !== STOP) failure = e;
        done = true;
        member.terminate();
      }
    };
    member.start();
  });
  unzip.register(UnzipInflate);
  const input = fs.createReadStream(file, { highWaterMark: 4096 });
  try {
    for await (const chunk of input) {
      signal?.throwIfAborted();
      unzip.push(chunk, false);
      if (done) break;
    }
    if (!done) unzip.push(new Uint8Array(), true);
  } finally {
    input.destroy();
  }
  if (failure) throw failure;
  return found;
}
async function parseMember(
  file,
  name,
  handlers,
  maxBytes = 8 * 1024 * 1024,
  signal,
) {
  const parser = new SaxesParser({ xmlns: false }),
    decoder = new TextDecoder("utf-8");
  let bytes = 0;
  for (const [event, fn] of Object.entries(handlers)) parser.on(event, fn);
  return zipMember(
    file,
    name,
    (data, final) => {
      bytes += data.length;
      if (bytes > maxBytes) throw Error("文档结构超出本地标题读取上限。");
      parser.write(decoder.decode(data, { stream: !final }));
      if (final) parser.close();
    },
    signal,
  );
}
const local = (n) => String(n).split(":").at(-1),
  attr = (node, key) => node.attributes[key] ?? node.attributes["w:" + key];
async function wordOpening(file, signal) {
  const zip = (...args) => zipMember(...args, signal),
    parse = (file, name, handlers, max) =>
      parseMember(file, name, handlers, max, signal);
  let rendered = false,
    tail = "";
  await zip(file, "word/document.xml", (data) => {
    const s = tail + new TextDecoder().decode(data);
    if (s.includes("lastRenderedPageBreak")) {
      rendered = true;
      return false;
    }
    tail = s.slice(-40);
  });
  let text = "",
    paragraph = "",
    pages = 1,
    inText = false,
    kinds = new Set(),
    since = false;
  const limit = rendered ? 12000 : 300,
    flush = () => {
      text += paragraph.split("\f").map(whitespace).join("\f") + "\n";
      paragraph = "";
    };
  function boundary(kind) {
    if (!since && kinds.size && !kinds.has(kind)) {
      kinds.add(kind);
      return;
    }
    if (kind === "before" && pages === 1 && !(text + paragraph).trim()) return;
    if (pages >= 2) {
      flush();
      throw STOP;
    }
    pages++;
    paragraph += "\f";
    kinds = new Set([kind]);
    since = false;
  }
  await parse(file, "word/document.xml", {
    opentag(node) {
      const name = local(node.name);
      if (name === "t") inText = true;
      if (name === "tab") paragraph += " ";
      if (name === "lastRenderedPageBreak") boundary("rendered");
      if (name === "br") {
        if (attr(node, "type") === "page") boundary("manual");
        else paragraph += "\n";
      }
      if (
        name === "pageBreakBefore" &&
        !["0", "false"].includes(attr(node, "val"))
      )
        boundary("before");
    },
    text(value) {
      if (inText) {
        const available = limit - [...(text + paragraph)].length;
        paragraph += [...value].slice(0, Math.max(0, available)).join("");
        if (value.trim()) since = true;
        if ([...(text + paragraph)].length >= limit) {
          flush();
          throw STOP;
        }
      }
    },
    closetag(node) {
      const name = local(node.name);
      if (name === "t") inText = false;
      if (name === "p") flush();
    },
  });
  flush();
  return { text: [...text].slice(0, limit).join(""), paginated: rendered };
}
async function spreadsheetTitles(file, source, signal) {
  signal?.throwIfAborted();
  const parse = (file, name, handlers, max) =>
    parseMember(file, name, handlers, max, signal);
  const sheets = [],
    relations = new Map(),
    fonts = [],
    styles = [];
  let font = null,
    inXfs = false;
  await parse(
    file,
    "xl/workbook.xml",
    {
      opentag(n) {
        if (
          local(n.name) === "sheet" &&
          !["hidden", "veryHidden"].includes(n.attributes.state) &&
          sheets.length < 20
        )
          sheets.push({ name: n.attributes.name, id: n.attributes["r:id"] });
      },
    },
    2e6,
  );
  await parse(
    file,
    "xl/_rels/workbook.xml.rels",
    {
      opentag(n) {
        if (
          local(n.name) !== "Relationship" ||
          n.attributes.TargetMode === "External"
        )
          return;
        const target = n.attributes.Target || "",
          p = target.startsWith("/") ? target.slice(1) : "xl/" + target;
        if (!target.includes("..") && /^xl\/worksheets\/.+\.xml$/.test(p))
          relations.set(n.attributes.Id, p);
      },
    },
    2e6,
  );
  await parse(
    file,
    "xl/styles.xml",
    {
      opentag(n) {
        const name = local(n.name);
        if (name === "font") font = { size: 11, bold: false };
        if (name === "sz" && font) font.size = +n.attributes.val || 11;
        if (name === "b" && font)
          font.bold = !["0", "false"].includes(n.attributes.val);
        if (name === "cellXfs") inXfs = true;
        if (name === "xf" && inXfs) styles.push(+n.attributes.fontId || 0);
        if (fonts.length > 10000 || styles.length > 10000) throw STOP;
      },
      closetag(n) {
        if (local(n.name) === "font") {
          fonts.push(font);
          font = null;
        }
        if (local(n.name) === "cellXfs") inXfs = false;
      },
    },
    2e6,
  );
  const books = [];
  for (const sheet of sheets) {
    const member = relations.get(sheet.id);
    if (!member) continue;
    let row = 0,
      cell = null,
      inValue = false,
      count = 0;
    const cells = [];
    await parse(file, member, {
      opentag(n) {
        const name = local(n.name);
        if (name === "row") {
          row = +n.attributes.r || row + 1;
          if (row > 30) throw STOP;
        }
        if (name === "c") {
          if (++count > 2000) throw STOP;
          const ref = n.attributes.r || "",
            m = ref.match(/^([A-Z]{1,3})(\d+)$/i),
            col = m
              ? [...m[1].toUpperCase()].reduce(
                  (v, c) => v * 26 + c.charCodeAt(0) - 64,
                  0,
                )
              : 0,
            r = m ? +m[2] : row;
          cell =
            col >= 1 && r <= 30 && ((r <= 8 && col <= 16) || col <= 3)
              ? {
                  row: r,
                  col,
                  style: +n.attributes.s || 0,
                  kind: n.attributes.t || "",
                  value: "",
                  formula: false,
                }
              : null;
        }
        if (name === "f" && cell) cell.formula = true;
        if (name === "v" || name === "t") inValue = !!cell;
      },
      text(s) {
        if (inValue && cell) {
          cell.value += s;
          if (cell.value.length > 2000) throw STOP;
        }
      },
      closetag(n) {
        const name = local(n.name);
        if (name === "t" || name === "v") inValue = false;
        if (name === "c") {
          if (cell && !cell.formula) cells.push(cell);
          cell = null;
        }
      },
    });
    books.push({ sheet: sheet.name, cells });
  }
  const needed = new Set(
      books
        .flatMap((b) =>
          b.cells.filter((c) => c.kind === "s").map((c) => +c.value),
        )
        .filter((n) => Number.isInteger(n) && n >= 0 && n <= 100000),
    ),
    shared = new Map();
  if (needed.size) {
    let index = -1,
      inText = false,
      value = "",
      max = Math.max(...needed);
    await parse(
      file,
      "xl/sharedStrings.xml",
      {
        opentag(n) {
          if (local(n.name) === "si") {
            index++;
            value = "";
          }
          if (local(n.name) === "t") inText = needed.has(index);
        },
        text(s) {
          if (inText) {
            value += s;
            if (value.length > 2000) throw STOP;
          }
        },
        closetag(n) {
          if (local(n.name) === "t") inText = false;
          if (local(n.name) === "si") {
            if (needed.has(index)) shared.set(index, value);
            if (index >= max) throw STOP;
          }
        },
      },
      32 * 1024 * 1024,
    );
  }
  let result = [];
  for (const book of books) {
    const cells = book.cells.flatMap((c) => {
        const value =
          c.kind === "s"
            ? shared.get(+c.value)
            : ["inlineStr", "str"].includes(c.kind)
              ? c.value
              : null;
        return value?.trim() ? [{ ...c, value }] : [];
      }),
      first = Math.min(...cells.map((c) => c.row)),
      top = cells.filter((c) => c.row === first).length;
    const lines = cells
      .filter((c) => c.row <= 8)
      .map((c) => ({
        text: c.value,
        prominent:
          fonts[styles[c.style]]?.size >= 14 ||
          fonts[styles[c.style]]?.bold ||
          (c.row === first && top <= 2 && [...c.value].length >= 5),
      }));
    result.push(
      ...titleSuggestions(
        [{ index: 0, lines }],
        source + " · " + book.sheet,
      ).map((c) => ({
        ...c,
        evidence: c.evidence.replace("首页", "Excel 表头"),
      })),
    );
    function runs(values, direction) {
      let run = [];
      const emit = () => {
        const name = run.map((c) => c.value).join("");
        if (
          [...name].length >= 4 &&
          /\p{Script=Han}/u.test(name) &&
          looksLikeTitle(name)
        )
          result.push({
            name: cleanTitle(name),
            evidence: direction + "表头 · " + source + " · " + book.sheet,
          });
      };
      for (const c of values) {
        const value = c.value.trim(),
          last = run.at(-1),
          adjacent =
            !last ||
            (direction === "横向"
              ? c.col === last.col + 1
              : c.row === last.row + 1);
        if ([...value].length === 1 && /\p{L}/u.test(value) && adjacent)
          run.push({ ...c, value });
        else {
          emit();
          run = [];
          if ([...value].length === 1 && /\p{L}/u.test(value))
            run.push({ ...c, value });
        }
      }
      emit();
    }
    for (let row = 1; row <= 8; row++)
      runs(
        cells.filter((c) => c.row === row).sort((a, b) => a.col - b.col),
        "横向",
      );
    for (let col = 1; col <= 3; col++)
      runs(
        cells.filter((c) => c.col === col).sort((a, b) => a.row - b.row),
        "纵向",
      );
  }
  const seen = new Set();
  return result
    .filter((c) => !seen.has(c.name) && seen.add(c.name))
    .slice(0, 12);
}
module.exports = {
  whitespace,
  cleanTitle,
  usableTitle,
  looksLikeTitle,
  textPages,
  titleSuggestions,
  wordOpening,
  spreadsheetTitles,
  zipMember,
  parseMember,
};
