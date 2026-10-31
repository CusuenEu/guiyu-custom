const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  { breadcrumbs, destination } = require("../src/navigation.cjs");
test("project ancestor navigation normalizes dot components without escaping or changing stored Unicode spelling", () => {
  const root = "C:\\资料\\项目",
    current = root + "\\招标文件\\附件\\当前";
  assert.equal(breadcrumbs(root, current, "项目根目录")[0].name, "项目根目录");
  assert.equal(destination(current + "\\..\\..\\..", root, current), root);
  assert.equal(destination("C:\\资料", root, current), null);
  assert.equal(destination(root + "-other", root, current), null);
  assert.equal(destination(root + "\\另一个分支", root, current), null);
  assert.equal(breadcrumbs(root, root + "\\..\\其他").length, 0);
  assert.equal(
    breadcrumbs("\\\\server\\share\\项目", "\\\\SERVER\\share\\项目\\附件")
      .length,
    2,
  );
  const unicode = "/tmp/Cafe\u0301/项目";
  assert.equal(breadcrumbs(unicode, unicode + "/附件")[0].path, unicode);
});
