"use strict";
const path = require("node:path");
const segmenter = new Intl.Segmenter();

function characters(name) {
  return Array.from(segmenter.segment(name), ({ segment, index }) => ({
    index,
    value: /^[\p{L}\p{N}]/u.test(segment)
      ? segment.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase()
      : null,
  }));
}

// Track the longest matching suffix ending at each position. Only runs of
// two or more characters contribute to coverage, even if runs overlap.
function coveredPositions(ends) {
  const covered = Array(ends.length).fill(false);
  let leftmost = ends.length;
  for (let index = ends.length - 1; index >= 0; index--) {
    if (ends[index] >= 2) leftmost = Math.min(leftmost, index + 1 - ends[index]);
    covered[index] = index >= leftmost;
  }
  return covered;
}

function continuousMatch(filename, project) {
  const suffixes = Array(project.length + 1).fill(0);
  const fileEnds = Array(filename.length).fill(0);
  const projectEnds = Array(project.length).fill(0);
  let longest = 0;
  for (let fileIndex = 0; fileIndex < filename.length; fileIndex++) {
    const value = filename[fileIndex].value;
    for (let index = project.length - 1; index >= 0; index--) {
      const length = value !== null && value === project[index].value ? suffixes[index] + 1 : 0;
      suffixes[index + 1] = length;
      fileEnds[fileIndex] = Math.max(fileEnds[fileIndex], length);
      projectEnds[index] = Math.max(projectEnds[index], length);
      longest = Math.max(longest, length);
    }
  }
  if (longest < 2) return null;
  const covered = coveredPositions(projectEnds);
  const count = Math.min(covered.filter(Boolean).length, coveredPositions(fileEnds).filter(Boolean).length);
  return { longest, count, covered };
}

function matchingRanges(name, project, covered) {
  const ranges = [];
  for (let index = 0; index < covered.length; index++) {
    if (!covered[index]) continue;
    const start = project[index].index, end = project[index + 1]?.index ?? name.length;
    const previous = ranges.at(-1);
    if (previous && previous[1] === start) previous[1] = end;
    else ranges.push([start, end]);
  }
  return ranges;
}

function rank(projects, items) {
  const filenames = items.map(({ name, folder }) => {
    const extension = folder ? "" : path.extname(name);
    return characters(name.slice(0, name.length - extension.length));
  }).filter(name => name.length >= 2);
  const recommendations = [];
  for (const project of projects) {
    const name = characters(project.name);
    const covered = Array(name.length).fill(false);
    let longest = 0, total = 0;
    for (const filename of filenames) {
      const match = continuousMatch(filename, name);
      if (!match) continue;
      longest = Math.max(longest, match.longest);
      total += match.count;
      for (let index = 0; index < covered.length; index++) covered[index] ||= match.covered[index];
    }
    if (longest < 2) continue;
    recommendations.push({
      ...project, longest, total,
      evidence: `最长连续匹配 ${longest} 个字符，累计匹配 ${total} 个字符`,
      matchingRanges: matchingRanges(project.name, name, covered),
    });
  }
  return recommendations.sort((a, b) =>
    b.longest - a.longest || b.total - a.total || a.name.localeCompare(b.name, "zh", { numeric: true }));
}

module.exports = { rank };
