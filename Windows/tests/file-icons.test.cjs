"use strict";
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const icons=require('../src/file-type-icons.js'),assets=path.join(__dirname,'../assets/file-icons'),manifest=require('../assets/file-icons/manifest.json');
test('all 45 file icons and 334 case-insensitive extension aliases resolve to actual offline assets',()=>{
 assert.equal(manifest.types.length,45);let aliases=0;
 for(const type of manifest.types){
  const svg=fs.readFileSync(path.join(assets,type.id+'.svg'),'utf8');assert.match(svg,/<svg\b/);assert.doesNotMatch(svg,/<(?:script|foreignObject|text)\b|(?:href|xlink:href)=/i);
  for(const ext of type.extensions){assert.equal(icons.identify('示例.'+ext.toUpperCase()).id,type.id,ext);aliases++;}
 }
 assert.equal(aliases,334);
});
test('format identity depends on the actual suffix, with compound paths, folders, bundles and unknown files handled explicitly',()=>{
 for(const [file,id]of [['项目计划.xlsx','excel'],['进度.mpp','project'],['C:\\测试\\网页.HTML','html'],['/目录/归档.TAR.GZ','archive'],['示意图.SVG','svg'],['安装包.msi','installer'],['安装镜像.dmg','disk'],['普通程序.exe','application'],['源稿.psd','photoshop'],['未知.zzz','unknown'],['没有后缀','unknown']])assert.equal(icons.identify(file).id,id,file);
 assert.equal(icons.identify('普通目录',{isDirectory:true}),null);assert.equal(icons.identify('目录.docx',{isDirectory:true}),null);
 assert.equal(icons.identify('归屿.app',{isDirectory:true}).id,'application');assert.equal(icons.identify('普通别名',{isShortcut:true}).id,'shortcut');
});
test('the production renderer loads the shared map and renders safe fixed icon URLs in every list',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../src/index.html'),'utf8'),ui=fs.readFileSync(path.join(__dirname,'../src/ui.cjs'),'utf8');
 assert(html.indexOf('src="file-type-icons.js"')<html.indexOf('src="ui.cjs"'));
 const start=ui.indexOf('const icon = (e) =>'),end=ui.indexOf('\nlet data,',start);assert(start>=0&&end>start);
 const renderer=ui.slice(start,end)+'\nicon(entry)';
 const result=vm.runInNewContext(renderer,{GuiyuFileIcons:icons,folder:'FOLDER',entry:{name:'恶意\" onerror=alert(1) .HTML'}});
 assert.match(result,/data-file-type="html"/);assert.match(result,/src="\.\.\/assets\/file-icons\/html.svg"/);assert(!result.includes('onerror'));
 assert.equal(vm.runInNewContext(renderer,{GuiyuFileIcons:icons,folder:'FOLDER',entry:{name:'目录',folder:true}}),'FOLDER');
});
