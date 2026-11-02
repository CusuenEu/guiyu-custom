"""Native Finder drag-to-Applications installer; no Finder automation needed."""
application = defines['app']
format = 'UDZO'
filesystem = 'HFS+'
files = [(application, '归屿.app')]
symlinks = {'应用程序': '/Applications'}
# Do not set FinderInfo on the signed app merely to hide its extension:
# codesign --strict rejects that extra metadata. Finder owns name display.
icon = application + '/Contents/Resources/AppIcon.icns'
background = defines['background']
window_rect = ((200, 160), (660, 420))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_locations = {'归屿.app': (180, 210), '应用程序': (480, 210)}
icon_size = 100
text_size = 14
label_pos = 'bottom'
arrange_by = None
grid_spacing = 64
include_icon_view_settings = True
include_list_view_settings = False
