"use strict";
// Broad organization/geography/document words are not project identity evidence.
const generic = /招投标文件|招标文件|投标文件|采购文件|技术方案|实施方案|有限责任公司|股份有限公司|有限公司|中国|贵州省|贵州|集团|公司|项目|合同|方案|文件|服务|采购|建设|租赁|年度|运维|维护|工程|报告|资料/g;
function identity(text) {
  return String(text).normalize("NFKC").toLowerCase().replace(/\.[a-z0-9]{1,8}$/i, "")
    .replace(generic, "").replace(/\d{4}[-年/.]?\d{1,2}(?:[-月/.]?\d{1,2}日?)?/g, "")
    .replace(/[^\p{L}\p{N}]/gu, "");
}
function codes(text) { return String(text).toUpperCase().match(/\b[A-Z]{2,}(?:[-_]\d{2,}){2,}\b/g) || []; }
function score(name, text) {
  if (/^[\d\s年月日月.\-_/]+$/.test(name)) return { score: 0 };
  if (codes(name).some(code => codes(text).includes(code))) return { score: 100, evidence: "项目编号完全一致" };
  const a = identity(name), b = identity(text);
  if (a.length < 4 || b.length < 4 || !/\p{L}/u.test(a) || !/\p{L}/u.test(b)) return { score: 0 };
  if (a === b || a.includes(b) || b.includes(a)) return { score: 95, evidence: "明确的项目名称一致" };
  const grams = value => new Set(Array.from({ length: Math.max(0, value.length - 2) }, (_, i) => value.slice(i, i + 3)));
  const x = grams(a), y = grams(b), common = [...x].filter(g => y.has(g)).length;
  const confidence = Math.floor(200 * common / (x.size + y.size));
  return common >= 3 && confidence >= 75 ? { score: confidence, evidence: "项目名称高度一致" } : { score: 0 };
}
function rank(projects, texts) {
  return projects.map(project => {
    let best = { score: 0, evidence: "可手动搜索选择" };
    // Weak hits from different files/lines must never accumulate into a match.
    for (const text of texts) for (const line of String(text).split(/[\r\n]+/)) {
      const candidate = score(project.name, line);
      if (candidate.score > best.score) best = candidate;
    }
    return { ...project, ...best };
  }).sort((a, b) => b.score - a.score || a.name.localeCompare(b.name, "zh"));
}
module.exports = { rank, identity, score };
