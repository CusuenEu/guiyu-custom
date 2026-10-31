$ErrorActionPreference='Stop'
foreach($kind in @('*','Directory')){
 foreach($pair in @(@('GuiyuName','归屿 · 智能命名','--smart-name'),@('GuiyuArchive','归屿 · 智能归档','--smart-archive'))){
  $subkey='Software\Classes\'+$kind+'\shell\'+$pair[0]
  if($env:GUIYU_MENU_ACTION -eq 'remove'){
   [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subkey,$false)
  }else{
   $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subkey)
   try{$key.SetValue('',$pair[1]);$key.SetValue('Icon',$env:GUIYU_EXE)}finally{$key.Dispose()}
   $command=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subkey+'\command')
   try{$command.SetValue('','"'+$env:GUIYU_EXE+'" '+$pair[2]+' "%1"')}finally{$command.Dispose()}
  }
 }
}
