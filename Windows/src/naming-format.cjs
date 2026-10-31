// Shared rules for the sandboxed editor and local file-operation checks.
(function (host) {
  "use strict";
  const formats = Object.freeze(["nameOnly", "month", "monthDay", "category"]);
  function settings(value) {
    const rules = {
      folder: value?.folder ?? "nameOnly",
      document: value?.document ?? "nameOnly",
      dateSource: value?.dateSource ?? "today",
    };
    if (
      !formats.includes(rules.folder) ||
      !formats.includes(rules.document) ||
      !["today", "created"].includes(rules.dateSource)
    )
      throw Error("命名规则无效。");
    return rules;
  }
  function literalStem(value, ext = "") {
    return ext && value.endsWith(ext) ? value.slice(0, -ext.length) : value;
  }
  function cleanTitle(value) {
    return String(value)
      .replace(/(?<=\p{Script=Han})\s*\r?\n\s*(?=\p{Script=Han})/gu, "")
      .replace(/\s+/g, " ")
      .trim()
      .replace(/[/\\:：*?"<>|\x00-\x1f\x7f]/g, "-")
      .replace(/^[.\s]+|[.\s]+$/g, "");
  }
  function cleanRecognizedText(value) {
    return String(value ?? "")
      .replace(/\s+/gu, "")
      .replace(/[<>:"/\\|?*？。：\x00-\x1f\x7f]/g, "")
      .replace(/^[.]+|[.]+$/g, "");
  }
  function editedName(value, ext = "", sanitize = false) {
    const raw = literalStem(value.trim(), ext);
    const stem = sanitize ? cleanTitle(raw) : raw.trim();
    if (!stem) throw Error("请填写新名称。");
    return stem + ext;
  }
  function candidateEditor(result, candidate) {
    if (!candidate)
      return result.fallback
        ? literalStem(result.originalName || result.entry.name, result.ext)
        : "";
    return (
      candidate.editableName ??
      (result.format === "category"
        ? [candidate.prefix ?? result.prefix, candidate.name]
            .filter(Boolean)
            .join(" ")
        : candidate.name)
    );
  }
  function candidateBatch(result, candidate) {
    if (!candidate)
      return result.fallback
        ? literalStem(result.originalName || result.entry.name, result.ext)
        : "";
    return literalStem(
      candidate.proposedName ??
        [candidate.prefix ?? result.prefix, candidate.name]
          .filter(Boolean)
          .join(" ") + result.ext,
      result.ext,
    );
  }
  function validatePrefix(name, format) {
    if (format === "month" && !/^(?:1[0-2]|[1-9])月\s+\S[\s\S]*$/.test(name))
      throw Error("月份必须为1至12月，并填写识别名称。");
    if (format === "monthDay") {
      const m = name.match(/^(\d{2})(\d{2})\s+\S/),
        date = m && new Date(2000, +m[1] - 1, +m[2]);
      if (!m || date.getMonth() !== +m[1] - 1 || date.getDate() !== +m[2])
        throw Error("请保留有效的四位MMDD前缀，并填写识别名称。");
    }
    if (!name.trim()) throw Error("请填写新名称。");
  }
  const formatter = Object.freeze({
    formats,
    settings,
    literalStem,
    editedName,
    cleanTitle,
    cleanRecognizedText,
    candidateEditor,
    candidateBatch,
    validatePrefix,
  });
  if (typeof module !== "undefined" && module.exports)
    module.exports = formatter;
  else host.GuiyuNaming = formatter;
})(globalThis);
