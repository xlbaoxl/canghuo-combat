"""One-time, no-network completion of the already staged documentation archive."""
from pathlib import Path
import hashlib, json, runpy
root=Path.cwd().resolve()
expected={
 'README.md':'984899f1eb103f8fb100f2fa759390a1d90f6197',
 'research/来源与文件成果索引.md':'30ef9df566058b857d27e09a7c5bf254fb08e473',
 'docs/实施状态与迁移清单.md':'54336f23824a934868a1b7c5b0f167f00071b97f',
 'migration/artifact_inventory.json':'7900857562f13c054e665a51bbde7e6c663aeb35'
}
texts={}
for name, blob in expected.items():
 raw=(root/name).read_bytes()
 if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=blob:
  raise ValueError('Concurrent change; refusing replacement: '+name)
 texts[name]=raw.decode('utf-8')

def change(name,old,new):
 if texts[name].count(old)!=1:raise ValueError('Expected exact text missing: '+name)
 texts[name]=texts[name].replace(old,new)

change('README.md','R4只将CRLF换行为LF，原始与归档哈希分别记录；未改术语和结论。','R4的8份正文已恢复为与原ZIP逐字节一致；此前明确登记的CRLF→LF转换保留在历史指纹中，当前不再有换行转换。术语、结构和结论不变。')
change('README.md','本地持有原始附件时可追加`--artifacts-dir`核对原件及CRLF→LF转换。','本地持有原始附件时可追加`--artifacts-dir`核对12份原件、37个研究成员和已归档正文的原字节。追加`--require-complete`会在存在迁移缺口时明确失败。')
change('research/来源与文件成果索引.md','唯一转换是CRLF换行为LF；文字、结构、证据ID和原链接保持，不用新摘要替代原文。源字节与归档字节分别核对。','本轮恢复8份正文的原CRLF字节，大小与SHA256均与原ZIP成员一致；保留此前LF版本的指纹作为转换历史。文字、结构、证据ID和原链接保持，不用新摘要替代原文。')
change('research/来源与文件成果索引.md','原件按原版本保留内容；本轮R4 Markdown明确将CRLF转为LF，源和目标各记哈希，不宣称原字节完全相同。','原件按原版本保留内容；当前R4的8份主正文与逸剑报告均逐字节保存。此前CRLF→LF转换经过可逆恢复并核对原件哈希，历史转换记录不删除。')
change('docs/实施状态与迁移清单.md','**归档边界：**R4的8份Markdown仅做CRLF→LF，不改正文；另外28个成员和原ZIP未上传。逸剑报告保持原字节。','**归档边界：**R4的8份Markdown已经恢复为与原ZIP逐字节一致；另外28个成员和原ZIP未上传。逸剑报告保持原字节。')
change('docs/实施状态与迁移清单.md','**工程边界：**已读取并核对旧源导出的173个文件（171个模块文件与2份策划），但没有将运行代码/二进制资产写入新仓。本轮尝试的临时下载凭据写入和跨仓树对象写入被工具安全检查拒绝，未重试绕过；未启用的导入脚本/工作流已从本轮分支头移除。此前R2导入流程还记录了旧仓请求404；导出取得与目标迁入不能混同。','**工程边界：**已读取并核对旧源导出的173个文件（171个模块文件与2份策划），但没有将运行代码/二进制资产写入新仓。本次续接的导入流程`37905170132`在下载原件时返回HTTP403，后续写入与提交步骤未运行；跨仓直接引用旧blob返回422，不是一次成功迁移。此前原仓只读请求测试记录HTTP404，工作流结束为success也不意味着传输成功。源导出已取得与目标已迁入分别记录。本轮归档PR不合入临时传输票据，不改变访问控制，不强推其他准备分支。')
texts['docs/实施状态与迁移清单.md']+='''
## 9. 本批交付检查口径

归档完整性检查逐项核验真实文件、哈希、成员映射和当前文档链接。仅对原始历史报告中指向同包明确待迁成员的链接记录缺口；新的现行文档不能用这个例外跳过坏链接。`--require-complete`保持整体迁移未完成时失败，不能用归档检查PASS宣称全量迁库。

16项反例覆盖原件被修改、换行被错误归一、伪造已归档状态、错误映射、路径越界和虚假完成。原件校验不执行研究包内脚本，不调用游戏。具体运行结果由PR检查与下载记录确认，不复制3.0.1历史游戏测试数量。

## 10. 已有原包时的可执行迁入入口

[离线迁移工具](../tools/import_verified_package.py)只接受已固定哈希的R4 ZIP或e101fca源码导出。默认只核验，显式`--write`才复制；既有不同内容会拒绝覆盖。它不下载、不运行游戏、不提交、不推送，也不改变仓库权限。

```sh
python tools/import_verified_package.py --kind research --input /实际路径/combat_research_20260930_R4_final.zip
python tools/import_verified_package.py --kind module --input /实际路径/combat-source.zip
```

先在新仓的干净工作分支检查计划，再追加`--write`；研究原文写入原件目录，源码保留modules/training-camp，旧两份策划放历史目录。完成物理写入后，另行同步本页、来源索引和整包归档状态，通过检查后提交PR。工具在隔离本地目录中实际演练了36份研究原件、173份源文件、重复导入与拒绝覆盖；这不等于它们已经推到本仓。

固定源码ZIP未记录Git文件模式和全部提交历史，工具明确保留这个限制；迁入后还要检查脚本启动方式、资源引用、旧文档相对路径与新仓真实运行。不能只看到导入成功就宣布工程验收完成。
'''
inv=json.loads(texts['migration/artifact_inventory.json'])
inv['manifest_version']=3
inv['source_migration_blocker']='Source export verified locally, but repository import run 37905170132 failed with HTTP 403 before any source write/commit. Cross-repository blob reuse rejected with HTTP 422. Full source/assets and release attachments remain pending; no access-control workaround.'
texts['migration/artifact_inventory.json']=json.dumps(inv,ensure_ascii=False,indent=2)+'\n'
receipt={
 'source_repository':'xlbaoxl/canghuo-game','source_commit':'e101fca146bf340d8738dbaa3931c827e4efc227',
 'source_export_run':37821554938,'source_archive_sha256':'3c6937b4ef35a839fd95a2b4c19ddc63ae85089782dd10d6d5a47c3add95a9d9',
 'files_verified':173,'module_files':171,'total_bytes':47956414,
 'checks':['byte count','SHA256','Git blob SHA1'],'result':'PASS',
 'destination_imported':False,'godot_executed':False,
 'scope':'Source export identity only, not repository migration or new engine verification',
 'blocked_import_run':37905170132,'blocked_import_http_status':403
}
new=root/'migration/source_export_verification.json'
if new.exists():raise ValueError('Source verification receipt already exists; review before replacing')
# Restore only bytes that match the registered original SHA, then publish metadata.
runpy.run_path(str(root/'tools/restore_original_line_endings.py'),run_name='__main__')
for name,text in texts.items():(root/name).write_text(text,encoding='utf-8')
new.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(root/'.gitattributes').write_text('*.py text eol=lf\n*.yml text eol=lf\nresearch/originals/** -text\narchive/** -text\nmodules/training-camp/** -text\n',encoding='utf-8')
print('Restored declared research bytes and updated four checked documents/receipts. No game code or assets imported.')
