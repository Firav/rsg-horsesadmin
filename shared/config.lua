Config = {}

Config.Debug = false

-- permission level required to open the admin horse management menu
Config.Permissions = { 'admin', 'god' }

-- command and keybind
Config.Command = 'horseadmin'
Config.KeyBind  = 'PGUP' -- handled by the admin menu command; only used if you wire a separate thread

-- log channel used with rsg-log:server:CreateLog
Config.LogChannel = 'adminmenu'

-- default stable to offer when creating/recovering horses
Config.DefaultStable = 'valentine'

-- whether to send admin notifications to the acting admin
Config.NotifyAdmin = true