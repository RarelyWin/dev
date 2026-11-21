local Library = {}
Library.__index = Library
Library.Version = "0.01"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer and LocalPlayer:GetMouse()

Library.Theme = {
    BackgroundStart = Color3.fromRGB(14, 15, 17),
    BackgroundEnd = Color3.fromRGB(25, 26, 29),
    Surface = Color3.fromRGB(29, 30, 33),
    Surface2 = Color3.fromRGB(38, 39, 42),
    Surface3 = Color3.fromRGB(48, 49, 52),
    Accent = Color3.fromRGB(210, 212, 216),
    AccentDark = Color3.fromRGB(92, 94, 99),
    Text = Color3.fromRGB(242, 243, 245),
    Muted = Color3.fromRGB(158, 160, 165),
    Stroke = Color3.fromRGB(7, 8, 9),
    Success = Color3.fromRGB(73, 183, 118),
    Warning = Color3.fromRGB(202, 173, 94),
    Error = Color3.fromRGB(190, 75, 110),
    Info = Color3.fromRGB(113, 110, 151),
}

local T = Library.Theme

local accentRegistry = {}
local function markAccent(object, prop)
    local props = accentRegistry[object]
    if not props then props = {}; accentRegistry[object] = props end
    props[prop] = true
end
local connections = {}
local iconCache = {}

local SUB_HEIGHT, SECTION_GAP, SUB_STAGGER = 38, 3, .035

local ROOT_DIR = "RarelyWin"
local FONT_DIR, SOUND_DIR, CACHE_DIR = ROOT_DIR .. "/fonts", ROOT_DIR .. "/sounds", ROOT_DIR .. "/cache"
local DEFAULT_TOGGLE_SOUND = "rbxassetid://6895079853"

local BUILTIN_FONT_ORDER, BUILTIN_FONTS = {}, {}
for _, item in ipairs(Enum.Font:GetEnumItems()) do
    if item ~= Enum.Font.Unknown then
        BUILTIN_FONTS[item.Name] = item
        table.insert(BUILTIN_FONT_ORDER, item.Name)
    end
end
local TEXT_CLASSES = {TextLabel = true, TextButton = true, TextBox = true}
local fontFiles, soundFiles = {}, {}
local fontAssets, familyFonts, soundIds = {}, {}, {}

local originalFonts = setmetatable({}, {
    __index = function(_, object)
        local family = object:GetAttribute("RW_FontFamily")
        if not family then return nil end
        local weight = Enum.FontWeight[object:GetAttribute("RW_FontWeight") or "Regular"] or Enum.FontWeight.Regular
        local style = Enum.FontStyle[object:GetAttribute("RW_FontStyle") or "Normal"] or Enum.FontStyle.Normal
        return Font.new(family, weight, style)
    end,
    __newindex = function(_, object, face)
        if face == nil then
            object:SetAttribute("RW_FontFamily", nil)
            return
        end
        object:SetAttribute("RW_FontFamily", face.Family)
        object:SetAttribute("RW_FontWeight", face.Weight.Name)
        object:SetAttribute("RW_FontStyle", face.Style.Name)
    end,
})
local ActiveFont = nil

local function ensureFolder(path)
    if not (makefolder and isfolder) then return end
    local built
    for part in string.gmatch(path, "[^/]+") do
        built = built and (built .. "/" .. part) or part
        if not isfolder(built) then pcall(makefolder, built) end
    end
end

local function fileExists(path)
    return isfile ~= nil and isfile(path) == true
end

pcall(function()
    if not (isfolder and listfiles and readfile and writefile) or not isfolder("RarelyWinUI") then return end
    local function copy(from, to)
        ensureFolder(to)
        for _, path in ipairs(listfiles(from)) do
            local name = tostring(path):match("[^/\\]+$")
            if name then
                local source, target = from .. "/" .. name, to .. "/" .. name
                if isfolder(source) then
                    copy(source, target)
                elseif not isfile(target) then
                    pcall(function() writefile(target, readfile(source)) end)
                end
            end
        end
    end
    copy("RarelyWinUI", ROOT_DIR)
end)

local function faceAsset(key, faces)
    if fontAssets[key] ~= nil then return fontAssets[key] or nil end
    fontAssets[key] = false
    local present = {}
    for _, face in ipairs(faces) do
        if fileExists(FONT_DIR .. "/" .. face.file) then table.insert(present, face) end
    end
    if #present == 0 or not (getcustomasset and writefile) then return nil end
    local ok, result = pcall(function()
        local list = {}
        for _, face in ipairs(present) do
            table.insert(list, {
                name = face.weight >= 600 and "Bold" or "Regular", weight = face.weight, style = "normal",
                assetId = getcustomasset(FONT_DIR .. "/" .. face.file),
            })
        end
        ensureFolder(CACHE_DIR)
        local descriptor = CACHE_DIR .. "/font_" .. (key:gsub("[^%w]", "")) .. ".font"
        writefile(descriptor, HttpService:JSONEncode({name = key, faces = list}))
        return getcustomasset(descriptor)
    end)
    if ok and result and result ~= "" then
        fontAssets[key] = result
    else
        warn("[RarelyWinUI] font '" .. key .. "' could not be loaded: " .. tostring(result))
    end
    return fontAssets[key] or nil
end

local function familyFont(key, faces, bold)
    local cacheKey = key .. (bold and ":bold" or ":regular")
    if familyFonts[cacheKey] ~= nil then return familyFonts[cacheKey] or nil end
    familyFonts[cacheKey] = false
    local asset = faceAsset(key, faces)
    if asset then
        local ok, font = pcall(Font.new, asset, bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular)
        if ok then familyFonts[cacheKey] = font end
    end
    return familyFonts[cacheKey] or nil
end

local function fileFont(name)
    local file = fontFiles[name]
    if not file then return nil end
    local regular = familyFont("file_" .. name, {{file = file, weight = 400}}, false)
    return regular and {regular = regular, bold = regular} or nil
end

local function isBoldFont(face)
    return face ~= nil and face.Weight.Value >= Enum.FontWeight.SemiBold.Value
end

local function applyFont(object, originalFont)
    if not ActiveFont then
        if originalFont then object.FontFace = originalFont end
        return
    end
    if ActiveFont.enum then
        local face = Font.fromEnum(ActiveFont.enum)
        if originalFont then face = Font.new(face.Family, originalFont.Weight, originalFont.Style) end
        object.FontFace = face
    else
        object.FontFace = isBoldFont(originalFont) and ActiveFont.bold or ActiveFont.regular
    end
end

local function scanFolder(dir, extensions, store)
    table.clear(store)
    local names = {}
    if not (listfiles and isfolder and isfolder(dir)) then return names end
    for _, path in ipairs(listfiles(dir)) do
        local file = tostring(path):match("[^/\\]+$") or ""
        local base, ext = file:match("^(.+)%.([^%.]+)$")
        if base and extensions[string.lower(ext)] then
            store[base] = file
            table.insert(names, base)
        end
    end
    table.sort(names)
    return names
end

local function soundIdFor(name)
    if name == nil or name == "Default" then return DEFAULT_TOGGLE_SOUND end
    local file = soundFiles[name]
    if not file then return nil end
    if soundIds[name] == nil then
        local ok, asset = pcall(getcustomasset, SOUND_DIR .. "/" .. file)
        soundIds[name] = (ok and asset and asset ~= "" and asset) or false
    end
    return soundIds[name] or nil
end

local function create(className, props, children)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
        if typeof(value) == "Color3" and value == T.Accent then markAccent(object, key) end
    end
    if TEXT_CLASSES[className] then
        local originalFont = object.FontFace
        originalFonts[object] = originalFont
        if ActiveFont then applyFont(object, originalFont) end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = object
    end
    return object
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function tween(object, time, props, style, direction)
    local info = TweenInfo.new(time or .18, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out)
    local animation = TweenService:Create(object, info, props)
    animation:Play()
    return animation
end

local function round(parent, radius)
    return create("UICorner", {CornerRadius = UDim.new(0, radius)}, {}), parent
end

local function addRound(parent, radius)
    local corner = create("UICorner", {CornerRadius = UDim.new(0, radius)})
    corner.Parent = parent
    return corner
end

local function stroke(parent, color, thickness, transparency)
    local item = create("UIStroke", {
        Color = color or T.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    item.Parent = parent
    return item
end

local function padding(parent, left, right, top, bottom)
    local item = create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0), PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or 0), PaddingBottom = UDim.new(0, bottom or top or 0),
    })
    item.Parent = parent
    return item
end

local function gradient(parent, first, last, rotation)
    local item = create("UIGradient", {
        Color = ColorSequence.new(first or T.BackgroundStart, last or T.BackgroundEnd),
        Rotation = rotation or 90,
    })
    item.Parent = parent
    return item
end

local function label(parent, text, size, font, color, align)
    local item = create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = text or "",
        TextColor3 = color or T.Text,
        TextSize = size or 16,
        Font = font or Enum.Font.GothamMedium,
        TextXAlignment = align or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    item.Parent = parent
    return item
end

local function autoCanvas(scroller, layout, extra)
    local function update()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + (extra or 0))
    end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update)
    update()
end

local function dragify(handle, target)
    local dragging, dragStart, startPosition
    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPosition = true, input.Position, target.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local holderScale = target.Parent and target.Parent:FindFirstChildOfClass("UIScale")
            if holderScale and holderScale.Scale > 0 then delta = delta / holderScale.Scale end
            target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function safeCallback(callback, ...)
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback, ...)
    if not ok then warn("[RarelyWinUI callback] " .. tostring(err)) end
end

local LUCIDE_URL = "https://raw.githubusercontent.com/mstudio45/lucide-roblox-direct/refs/heads/main/source.lua"
local LUCIDE_CACHE = CACHE_DIR .. "/lucide.lua"
local function loadLucide()
    if fileExists(LUCIDE_CACHE) then
        local ok, module = pcall(function() return (loadstring(readfile(LUCIDE_CACHE)))() end)
        if ok and type(module) == "table" then return true, module end
    end
    local ok, source = pcall(game.HttpGet, game, LUCIDE_URL)
    if not ok or type(source) ~= "string" then return false, source end
    local compiled, module = pcall(function() return (loadstring(source))() end)
    if not compiled then return false, module end
    if writefile then
        ensureFolder(CACHE_DIR)
        pcall(writefile, LUCIDE_CACHE, source)
    end
    return true, module
end
local _lucideOk, _lucideModule = loadLucide()

function Library:GetIcon(name)
    if iconCache[name] then return iconCache[name] end
    if not _lucideOk or type(_lucideModule) ~= "table" then return nil end
    local getter = _lucideModule.GetAsset or _lucideModule.getAsset
    if type(getter) ~= "function" then return nil end
    local ok, result = pcall(getter, name)
    if not ok then ok, result = pcall(getter, _lucideModule, name) end
    local asset = result
    if type(result)=="string" then asset={Url=result,ImageRectOffset=Vector2.zero,ImageRectSize=Vector2.zero} end
    if ok and type(asset)=="table" and type(asset.Url)=="string" then iconCache[name]=asset; return asset end
    return nil
end

function Library:GetIconStatus()
    if _lucideOk and type(_lucideModule)=="table" then return true,nil end
    return false,tostring(_lucideModule)
end

local function icon(parent, name, size, color)
    local asset = Library:GetIcon(name)
    local image = create("ImageLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Image = asset and asset.Url or "",
        ImageRectOffset = asset and asset.ImageRectOffset or Vector2.zero,
        ImageRectSize = asset and asset.ImageRectSize or Vector2.zero,
        ImageColor3 = color or T.Text,
        Size = UDim2.fromOffset(size or 20, size or 20),
    })
    image.Parent = parent
    return image
end

local function brand(parent, short, size)
    local holder = create("Frame", {BackgroundTransparency = 1, Size = size or UDim2.fromOffset(270, 58)})
    holder.Parent = parent
    local text = short and "RW" or "RARELYWIN"
    local shadow = label(holder, text, short and 52 or 46, Enum.Font.GothamBlack, T.Accent)
    shadow.Position = UDim2.fromOffset(-3, 3)
    shadow.Size = UDim2.fromScale(1, 1)
    shadow.TextScaled = true
    local shadowConstraint=create("UITextSizeConstraint",{MinTextSize=12,MaxTextSize=short and 52 or 46}); shadowConstraint.Parent=shadow
    local front = label(holder, text, short and 52 or 46, Enum.Font.GothamBlack, T.Text)
    front.Size = UDim2.fromScale(1, 1)
    front.TextScaled = true
    local frontConstraint=create("UITextSizeConstraint",{MinTextSize=12,MaxTextSize=short and 52 or 46}); frontConstraint.Parent=front
    return holder
end

local function oneCornerCard(frame, radius)
    addRound(frame, radius or 15)
end

function Library:CreateWindow(options)
    options = options or {}
    local self = setmetatable({}, Library)
    self.Tabs, self.Keybinds, self.Flags, self.HUDRegistry = {}, {}, {}, {}
    self.ValueBinds = {}
    self.Visible = true

    local parent = options.Parent
    if not parent then
        local ok, hui = pcall(function() return gethui and gethui() end)
        parent = (ok and hui) or game:GetService("CoreGui")
    end

    local gui = create("ScreenGui", {
        Name = options.Name or ("RarelyWinUI_" .. HttpService:GenerateGUID(false)),
        ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 1000,
    })
    pcall(function() gui.Parent = parent end)
    if not gui.Parent and LocalPlayer then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    self.Gui = gui

    local main = create("CanvasGroup", {
        Name = "Window", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = options.Size or UDim2.fromOffset(980, 610), BackgroundColor3 = T.BackgroundStart,
        BorderSizePixel = 0, ClipsDescendants = true, ZIndex=50, GroupTransparency = .08,
    })

    local scaleHolder = create("Frame", {Name = "WindowHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(1, 1), ZIndex = 50})
    scaleHolder.Parent = gui
    main.Parent = scaleHolder
    addRound(main, 15); stroke(main, T.Stroke, 2)
    local mainGradientBackground=create("Frame",{Name="MainGradientBackground",BackgroundColor3=T.BackgroundStart,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=0})
    mainGradientBackground.Parent=main
    self.Main, self.OriginalSize = main, main.Size

    local mainScale = create("UIScale", {Scale = 1}); mainScale.Parent = scaleHolder
    self.MainScale = mainScale
    local grip = create("TextButton", {Name = "ScaleGrip", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -4), Size = UDim2.fromOffset(46, 16), ZIndex = 60})
    grip.Parent = main
    local gripLine = create("Frame", {BackgroundColor3 = T.Muted, BackgroundTransparency = .35, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 8, .5, 0), Size = UDim2.fromOffset(30, 4), ZIndex = 61})
    gripLine.Parent = grip; addRound(gripLine, 2)
    local tip = create("TextLabel", {BackgroundColor3 = Color3.fromRGB(15, 16, 19), BackgroundTransparency = .15, BorderSizePixel = 0,
        Text = "Drag to resize the menu", TextColor3 = Color3.fromRGB(226, 228, 233), TextSize = 13, Font = Enum.Font.GothamMedium,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), Visible = false, ZIndex = 900})
    tip.Parent = gui; addRound(tip, 6); padding(tip, 9, 9, 0, 0)
    local gripDrag = nil
    local function placeTip(pos) tip.Position = UDim2.fromOffset(pos.X + 14, pos.Y - 30) end
    connect(grip.MouseEnter, function() tween(gripLine, .12, {BackgroundColor3 = T.Accent, BackgroundTransparency = 0, Size = UDim2.fromOffset(34, 4)}); tip.Visible = true end)
    connect(grip.MouseLeave, function()
        if not gripDrag then tween(gripLine, .12, {BackgroundColor3 = T.Muted, BackgroundTransparency = .35, Size = UDim2.fromOffset(30, 4)}); tip.Visible = false end
    end)
    connect(grip.MouseMoved, function(x, y) placeTip(Vector2.new(x, y)) end)
    connect(grip.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            gripDrag = {Start = Vector2.new(input.Position.X, input.Position.Y), Scale = mainScale.Scale}
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if gripDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local pos = Vector2.new(input.Position.X, input.Position.Y)
            local d = pos - gripDrag.Start

            self:SetMenuScale(gripDrag.Scale + (d.Y - d.X) / 700)
            tip.Text = string.format("Click GUI Scale: %d%%", math.floor(mainScale.Scale * 100 + .5))
            placeTip(pos)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if gripDrag and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            gripDrag = nil
            tip.Visible = false; tip.Text = "Drag to resize the menu"
            tween(gripLine, .12, {BackgroundColor3 = T.Muted, BackgroundTransparency = .35, Size = UDim2.fromOffset(30, 4)})
            if self.MenuScaleControl then self.MenuScaleControl:Set(math.floor(mainScale.Scale * 100 + .5), true) end
        end
    end)
    self.Visible = true
    self.HUDElements = {}

    local modal = create("TextButton", {Name = "RW_MouseUnlock", Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Modal = true, Visible = true, AutoButtonColor = false})
    modal.Parent = main
    local keptIcon = nil
    pcall(function()
        RunService:BindToRenderStep("RW_MenuMouse", Enum.RenderPriority.Last.Value + 1, function()
            if modal.Visible ~= self.Visible then modal.Visible = self.Visible end
            if not self.Visible then
                if keptIcon ~= nil then UserInputService.MouseIconEnabled = keptIcon; keptIcon = nil end
                return
            end
            if keptIcon == nil then keptIcon = UserInputService.MouseIconEnabled end
            local custom = self.CursorState and self.CursorState.Enabled and self.CursorAssets and self.CursorAssets[self.CursorState.Style]
            if not custom and not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = true end
        end)
    end)

    local sidebar = create("Frame", {BackgroundColor3 = T.BackgroundStart, BackgroundTransparency = .03, BorderSizePixel = 0, Size = UDim2.new(0, 260, 1, 0), ClipsDescendants = true})
    sidebar.Parent = main
    self.Sidebar = sidebar
    local divider = create("Frame", {BackgroundColor3 = T.Stroke, BorderSizePixel = 0, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0)})
    divider.Parent = sidebar

    local titleBrand = brand(sidebar, options.CompactTitle == true, UDim2.new(1, -34, 0, 58))
    titleBrand.Position = UDim2.fromOffset(20, 13)
    local version = label(sidebar, "V. " .. tostring(options.Version or Library.Version), 18, Enum.Font.GothamBold)
    version.Position = UDim2.fromOffset(22, 67); version.Size = UDim2.fromOffset(125, 26)
    local uid = label(sidebar, "UID: " .. tostring(options.UID or 1), 18, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Right)
    uid.Position = UDim2.new(1, -130, 0, 67); uid.Size = UDim2.fromOffset(105, 26)

    local tabList = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(18, 105), Size = UDim2.new(1, -36, 1, -277), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 0, ScrollBarImageTransparency = 1, VerticalScrollBarInset = Enum.ScrollBarInset.None})
    tabList.Parent = sidebar
    local tabLayout = create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    tabLayout.Parent = tabList

    local settings = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.new(0, 18, 1, -112), Size = UDim2.new(1, -36, 0, 46)})
    settings.Parent = sidebar; settings.BackgroundColor3=T.Surface3; addRound(settings,9); self.SettingsButton=settings
    local settingsIcon = icon(settings, "settings", 25, T.Muted); settingsIcon.AnchorPoint=Vector2.new(.5,.5); settingsIcon.Position = UDim2.fromOffset(23,23)
    local settingsText = label(settings, "Settings", 18, Enum.Font.GothamBold); settingsText.Position = UDim2.fromOffset(47, 0); settingsText.Size = UDim2.new(1, -47, 1, 0)

    local profile = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -64), Size = UDim2.new(1, 0, 0, 64)})
    profile.Parent = sidebar
    local profileLine = create("Frame", {BackgroundColor3 = T.Stroke, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1)})
    profileLine.Parent = profile
    local detectedPlace="Unknown Place"; pcall(function() detectedPlace=MarketplaceService:GetProductInfo(game.PlaceId).Name end)
    local gameName = label(profile, options.Game or detectedPlace, 14, Enum.Font.GothamBold)
    gameName.Position = UDim2.fromOffset(20, 0); gameName.Size = UDim2.new(1, -70, 1, 0)
    self.GameLabel=gameName
    local bottomCollapse = create("TextButton", {Text="", AutoButtonColor=false, BackgroundColor3=T.Surface3, BorderSizePixel=0, Position=UDim2.new(1,-45,0,18), Size=UDim2.fromOffset(28,28), ZIndex=12})
    bottomCollapse.Parent=profile; addRound(bottomCollapse,7)
    local bottomCollapseIcon=icon(bottomCollapse,"chevron-left",17,T.Text); bottomCollapseIcon.AnchorPoint=Vector2.new(.5,.5); bottomCollapseIcon.Position=UDim2.fromScale(.5,.5); bottomCollapseIcon.ZIndex=13

    local collapse = create("TextButton", {Text = "‹", TextColor3 = T.Text, TextSize = 25, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Position = UDim2.new(1, -31, 0, 13), Size = UDim2.fromOffset(25, 25), ZIndex = 12})
    collapse.Parent = sidebar; collapse.Visible=false; addRound(collapse, 7)

    local topbar = create("Frame", {BackgroundColor3 = T.BackgroundStart, BackgroundTransparency = .04, BorderSizePixel = 0, Position = UDim2.fromOffset(260, 0), Size = UDim2.new(1, -260, 0, 64)})
    topbar.Parent = main
    local search = create("TextBox", {
        PlaceholderText = "Search...", PlaceholderColor3 = T.Muted, Text = "", ClearTextOnFocus = false,
        TextColor3 = T.Text, TextSize = 16, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Color3.fromRGB(130, 128, 145), BackgroundTransparency = .15, BorderSizePixel = 0,
        Position = UDim2.fromOffset(44, 14), Size = UDim2.new(1, -62, 0, 36),
    })
    search.Parent = topbar; addRound(search, 7); padding(search, 12, 12, 0, 0)
    local searchIcon = icon(topbar, "search", 22, T.Text); searchIcon.Position = UDim2.fromOffset(16, 21)
    local content = create("Frame", {BackgroundColor3 = T.BackgroundStart, BackgroundTransparency = 0, Position = UDim2.fromOffset(260, 64), Size = UDim2.new(1, -260, 1, -64), ClipsDescendants = true})
    content.Parent = main
    gradient(content, T.BackgroundStart, T.BackgroundEnd, 125)
    local backgroundImage=create("ImageLabel",{Name="CustomBackground",BackgroundTransparency=1,Image="",ImageTransparency=.35,ScaleType=Enum.ScaleType.Crop,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=0})
    backgroundImage.Parent=content; self.BackgroundImage=backgroundImage

    self.Sidebar, self.TabList, self.Content, self.Search = sidebar, tabList, content, search
    self.Topbar, self.SidebarCollapsed = topbar, false
    dragify(topbar, main)

    function self:SetSidebarCollapsed(collapsed)
        self.SidebarCollapsed = collapsed == true
        local width = self.SidebarCollapsed and 72 or 260
        local collapseAsset=self:GetIcon(self.SidebarCollapsed and "chevron-right" or "chevron-left")
        if collapseAsset then bottomCollapseIcon.Image=collapseAsset.Url; bottomCollapseIcon.ImageRectOffset=collapseAsset.ImageRectOffset; bottomCollapseIcon.ImageRectSize=collapseAsset.ImageRectSize end
        tween(sidebar, .28, {Size = UDim2.new(0, width, 1, 0)}, Enum.EasingStyle.Quint)
        tween(topbar, .28, {Position = UDim2.fromOffset(width, 0), Size = UDim2.new(1, -width, 0, 64)}, Enum.EasingStyle.Quint)
        tween(content, .28, {Position = UDim2.fromOffset(width, 64), Size = UDim2.new(1, -width, 1, -64)}, Enum.EasingStyle.Quint)
        titleBrand.Visible = not self.SidebarCollapsed; version.Visible = not self.SidebarCollapsed; uid.Visible = not self.SidebarCollapsed
        settingsText.Visible = not self.SidebarCollapsed; gameName.Visible=not self.SidebarCollapsed; profile.Visible=true
        settings.Size = self.SidebarCollapsed and UDim2.fromOffset(36,46) or UDim2.new(1,-36,0,46)
        settingsIcon.Position = self.SidebarCollapsed and UDim2.new(.5,0,.5,0) or UDim2.fromOffset(23,23)
        for _, tab in ipairs(self.Tabs) do
            tab.Title.Visible = not self.SidebarCollapsed
            if tab.Icon then tab.Icon.Position = self.SidebarCollapsed and UDim2.new(.5,-12,.5,-12) or UDim2.fromOffset(11,9) end
            for _,sub in ipairs(tab.Subcategories) do
                sub.Title.Visible=not self.SidebarCollapsed
                sub.Icon.Position=self.SidebarCollapsed and UDim2.new(.5,-10,.5,-10) or UDim2.fromOffset(28,9)
            end
        end
    end
    connect(collapse.MouseButton1Click, function() self:SetSidebarCollapsed(not self.SidebarCollapsed) end)
    connect(bottomCollapse.MouseButton1Click, function() self:SetSidebarCollapsed(not self.SidebarCollapsed) end)

    connect(search:GetPropertyChangedSignal("Text"), function()
        for _, tab in ipairs(self.Tabs) do
            if tab.Page.Visible then tab:ApplyFilter() end
        end
    end)

    connect(UserInputService.InputBegan, function(input, processed)
        local point=input.Position
        local pointer=input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.MouseButton2 or input.UserInputType==Enum.UserInputType.Touch
        if pointer and self.OpenDropdown then
            local open=self.OpenDropdown; local bp,bs=open.Button.AbsolutePosition,open.Button.AbsoluteSize; local mp,ms=open.Menu.AbsolutePosition,open.Menu.AbsoluteSize
            local insideButton=point.X>=bp.X and point.X<=bp.X+bs.X and point.Y>=bp.Y and point.Y<=bp.Y+bs.Y
            local insideMenu=point.X>=mp.X and point.X<=mp.X+ms.X and point.Y>=mp.Y and point.Y<=mp.Y+ms.Y
            if not insideButton and not insideMenu then open:Close() end
        end
        if pointer and self.OpenColorPicker then
            local picker=self.OpenColorPicker; local sp,ss=picker.Swatch.AbsolutePosition,picker.Swatch.AbsoluteSize; local pp,ps=picker.Popup.AbsolutePosition,picker.Popup.AbsoluteSize
            local insideSwatch=point.X>=sp.X and point.X<=sp.X+ss.X and point.Y>=sp.Y and point.Y<=sp.Y+ss.Y
            local insidePopup=point.X>=pp.X and point.X<=pp.X+ps.X and point.Y>=pp.Y and point.Y<=pp.Y+ps.Y
            if not insideSwatch and not insidePopup then picker:Close() end
        end
        if pointer and self.OpenBindPopup then
            local bp2=self.OpenBindPopup; local bbp,bbs=bp2.Button.AbsolutePosition,bp2.Button.AbsoluteSize; local bpp,bps=bp2.Popup.AbsolutePosition,bp2.Popup.AbsoluteSize
            local insideBindButton=point.X>=bbp.X and point.X<=bbp.X+bbs.X and point.Y>=bbp.Y and point.Y<=bbp.Y+bbs.Y
            local insideBindPopup=point.X>=bpp.X and point.X<=bpp.X+bps.X and point.Y>=bpp.Y and point.Y<=bpp.Y+bps.Y
            if not insideBindButton and not insideBindPopup then bp2:Close() end
        end
        local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
        if input.KeyCode == toggleKey then
            if not UserInputService:GetFocusedTextBox() then
                self:ToggleUI()
                return
            end
        end

        if processed then return end
        for _, bind in ipairs(self.Keybinds) do
            if input.KeyCode == bind.Key or input.UserInputType == bind.Key then safeCallback(bind.Callback, bind.Key) end
        end
        for _, entry in ipairs(self.ValueBinds) do
            for _, vbind in ipairs(entry.Binds) do
                if vbind.Key and (input.KeyCode == vbind.Key or input.UserInputType == vbind.Key) then
                    if vbind.Mode == "Toggle" then
                        entry.Control:Set(not entry.Control.Value)
                    elseif vbind.Mode == "Hold" and not vbind.HoldActive then
                        vbind.HoldActive = true
                        vbind.PriorValue = entry.Control.Value
                        entry.Control:Set(vbind.Value)
                    end
                end
            end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        for _, entry in ipairs(self.ValueBinds) do
            for _, vbind in ipairs(entry.Binds) do
                if vbind.Mode == "Hold" and vbind.HoldActive and vbind.Key and (input.KeyCode == vbind.Key or input.UserInputType == vbind.Key) then
                    vbind.HoldActive = false
                    entry.Control:Set(vbind.PriorValue)
                end
            end
        end
    end)
    pcall(function()
        connect(GuiService.MenuOpened, function() self._hiddenByRobloxMenu=self.Visible; if self._hiddenByRobloxMenu then self.Main.Visible=false end end)
        connect(GuiService.MenuClosed, function() if self._hiddenByRobloxMenu and self.Visible then self.Main.Visible=true end; self._hiddenByRobloxMenu=false end)
    end)

    connect(settings.MouseButton1Click, function()
        if self.SettingsTab then self.SettingsTab:Select() end
    end)

    if options.ToggleButton ~= false then self:_createToggle(options.ToggleVariant or 1) end
    self:_buildSettingsSection()
    return self
end

function Library:_createToggle(variant)
    local oldPosition=self.ToggleButton and self.ToggleButton.Position or UDim2.fromOffset(18,72)
    if self.ToggleButton then self.ToggleButton:Destroy() end
    local button = create("TextButton", {
        Name = "UIToggle", Text = "", AutoButtonColor = false,
        BackgroundColor3 = T.BackgroundStart, BorderSizePixel = 0,
        Position = oldPosition, Size = variant == 2 and UDim2.fromOffset(255, 62) or UDim2.fromOffset(72, 72),
    })
    button.Parent = self.Gui; addRound(button, variant == 2 and 31 or 22); gradient(button, T.BackgroundStart, T.BackgroundEnd, 35)
    local word = variant == 2 and "RARELYWIN" or "RW"
    local wordSize = variant == 2 and 32 or 34
    local accent = label(button, word, wordSize, Enum.Font.GothamBlack, T.Accent, Enum.TextXAlignment.Center)
    accent.Position = UDim2.fromOffset(-1, 1); accent.Size = UDim2.fromScale(1, 1); accent.ZIndex = button.ZIndex + 1
    local front = label(button, word, wordSize, Enum.Font.GothamBlack, T.Text, Enum.TextXAlignment.Center)
    front.Size = UDim2.fromScale(1,1); front.ZIndex = button.ZIndex + 2
    connect(button.MouseButton1Click, function() self:ToggleUI() end)
    dragify(button, button)
    self.ToggleButton = button
    if self.HUDElements then self.HUDElements["Toggle UI Button"] = button end
    if self.InterfaceScale and self.InterfaceScale ~= 1 then local sc = Instance.new("UIScale"); sc.Name = "RW_InterfaceScale"; sc.Scale = self.InterfaceScale; sc.Parent = button end
    if self._selectedElements and self._selectedElements["Toggle UI Button"] ~= nil then
        button.Visible = self._selectedElements["Toggle UI Button"] == true
    end
end

function Library:SetMenuScale(scale)
    scale = math.clamp(tonumber(scale) or 1, .25, 1.25)
    if self.MainScale then self.MainScale.Scale = scale end
    self.MenuScale = scale
end

function Library:SetInterfaceScale(scale)
    scale = math.clamp(tonumber(scale) or 1, .25, 1.25)
    self.InterfaceScale = scale
    for _, element in pairs(self.HUDElements or {}) do
        local frame = typeof(element) == "Instance" and element or (type(element) == "table" and (element.Frame or element.Group)) or nil
        if typeof(frame) == "Instance" and frame:IsA("GuiObject") then
            local uiScale = frame:FindFirstChild("RW_InterfaceScale")
            if not uiScale then
                uiScale = Instance.new("UIScale"); uiScale.Name = "RW_InterfaceScale"; uiScale.Parent = frame
            end
            uiScale.Scale = scale
        end
    end
end

function Library:ToggleUI(state)
    if state == nil then state = not self.Visible end
    self.Visible = state
    local target = self.OriginalSize or self.Main.Size
    if state then
        self.Main.Visible = true
        self.Main.Size = UDim2.new(target.X.Scale, math.floor(target.X.Offset*.94), target.Y.Scale, math.floor(target.Y.Offset*.94))
        self.Main.GroupTransparency = 1
        tween(self.Main, .22, {Size = target, GroupTransparency = 0.08}, Enum.EasingStyle.Back)
    else
        tween(self.Main, .18, {Size = UDim2.new(target.X.Scale, math.floor(target.X.Offset*.94), target.Y.Scale, math.floor(target.Y.Offset*.94)), GroupTransparency = 1})
        task.delay(.19, function() if not self.Visible then self.Main.Visible = false end end)
    end
end

local function subcategoryMatches(tab, subcategory)
    return subcategory == nil or tab.ActiveSub == nil or subcategory == tab.ActiveSub.Name
end

local function setSubState(sub, shown, active, time, delay)
    sub.Token = (sub.Token or 0) + 1
    local token = sub.Token
    for _, animation in ipairs(sub.Tweens) do animation:Cancel() end
    table.clear(sub.Tweens)
    local item, image, title = sub.Button, sub.Icon, sub.Title
    title.TextColor3 = active and T.Text or T.Muted
    local function play()
        if sub.Token ~= token then return end
        local height = shown and SUB_HEIGHT or 0
        local background = shown and (active and .06 or 1) or 1
        local fade = shown and 0 or 1
        local slide = shown and 60 or 68
        if not time then
            item.Size = UDim2.new(1, 0, 0, height)
            item.BackgroundTransparency = background
            image.ImageTransparency = fade
            title.TextTransparency = fade
            title.Position = UDim2.fromOffset(slide, 0)
            item.Visible = shown
            return
        end
        if shown and not item.Visible then

            item.Size = UDim2.new(1, 0, 0, 0)
            image.ImageTransparency = 1
            title.TextTransparency = 1
            title.Position = UDim2.fromOffset(68, 0)
            item.Visible = true
        end
        table.insert(sub.Tweens, tween(item, time, {Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = background}, Enum.EasingStyle.Quint))
        table.insert(sub.Tweens, tween(image, time, {ImageTransparency = fade}))
        table.insert(sub.Tweens, tween(title, time, {TextTransparency = fade, Position = UDim2.fromOffset(slide, 0)}, Enum.EasingStyle.Quint))
        if not shown then
            task.delay(time, function() if sub.Token == token then item.Visible = false end end)
        end
    end
    if delay and delay > 0 then task.delay(delay, play) else play() end
end

function Library:Tab(options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local tab = {Library = self, Name = options.Name or "Tab", Cards = {}, Subcategories = {}, Panels = {}}

    if #self.Tabs > 0 and not options.Hidden and not options.Pinned then
        local gap = create("Frame", {Name = "SectionGap", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, SECTION_GAP), LayoutOrder = (#self.Tabs + 1) * 10 - 1})
        gap.Parent = self.TabList
    end
    local button = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = T.Surface3, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42)})
    button.Parent = self.TabList; button.LayoutOrder=(#self.Tabs+1)*10; addRound(button, 9)
    local image = icon(button, options.Icon or "menu", 24, T.Muted); image.Position = UDim2.fromOffset(11, 9)
    local title = label(button, tab.Name, 18, Enum.Font.GothamBold); title.Position = UDim2.fromOffset(48, 0); title.Size = UDim2.new(1, -48, 1, 0)
    local page = create("CanvasGroup", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28), Visible = false, GroupTransparency=1})
    page.Parent = self.Content
    local left = create("ScrollingFrame", {Name="Left", BackgroundTransparency=1, BorderSizePixel=0, Size=UDim2.new(.5,-6,1,0), CanvasSize=UDim2.fromOffset(0,0), ScrollBarThickness=0, ScrollBarImageTransparency=1}); left.Parent=page
    local right = create("ScrollingFrame", {Name="Right", BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(.5,6,0,0), Size=UDim2.new(.5,-6,1,0), CanvasSize=UDim2.fromOffset(0,0), ScrollBarThickness=0, ScrollBarImageTransparency=1}); right.Parent=page
    local leftLayout = create("UIListLayout", {Padding=UDim.new(0,12), SortOrder=Enum.SortOrder.LayoutOrder}); leftLayout.Parent=left
    local rightLayout = create("UIListLayout", {Padding=UDim.new(0,12), SortOrder=Enum.SortOrder.LayoutOrder}); rightLayout.Parent=right
    autoCanvas(left,leftLayout,6); autoCanvas(right,rightLayout,6)
    tab.Button, tab.Title, tab.Icon, tab.Page, tab.Left, tab.Right, tab.LeftLayout, tab.RightLayout = button, title, image, page, left, right, leftLayout, rightLayout
    if options.Hidden then button.Visible=false; button.Size=UDim2.fromOffset(0,0) end
    table.insert(self.Tabs, tab)

    function tab:ApplyFilter()
        local query = string.lower(self.Library.Search.Text)
        for _, card in ipairs(self.Cards) do
            local searchMatch = query == "" or string.find(string.lower(card.SearchText), query, 1, true) ~= nil
            card.Frame.Visible = searchMatch and subcategoryMatches(self, card.Subcategory)
        end
        for _, entry in ipairs(self.Panels) do
            entry.Frame.Visible = self.ActiveSub ~= nil and entry.Subcategory == self.ActiveSub.Name
        end
    end
    function tab:_setSubsShown(shown, time)
        for index, sub in ipairs(self.Subcategories) do
            setSubState(sub, shown, sub == self.ActiveSub, time, shown and (index - 1) * SUB_STAGGER or 0)
        end
    end
    function tab:ActivateSubcategory(sub)
        if self.ActiveSub == sub then return end
        self.ActiveSub = sub

        for _, other in ipairs(self.Subcategories) do
            setSubState(other, true, other == sub)
        end
        self:ApplyFilter()
    end
    function tab:Select()
        local library = self.Library
        if library.ActiveTab == self then return end
        local previous = library.ActiveTab
        for _, other in ipairs(library.Tabs) do
            other.Page.Visible = false
            tween(other.Button, .16, {BackgroundTransparency = 1})
        end
        if previous then previous:_setSubsShown(false, .2) end
        self.Page.Visible = true
        self.Page.GroupTransparency = 1
        tween(self.Page, .22, {GroupTransparency = 0})
        tween(self.Button, .16, {BackgroundTransparency = .05})
        if not self.ActiveSub then self.ActiveSub = self.Subcategories[1] end
        self:ApplyFilter()
        self:_setSubsShown(true, .26)
        if library.SettingsButton then tween(library.SettingsButton, .16, {BackgroundTransparency = self == library.SettingsTab and .05 or 1}) end
        library.ActiveTab = self
    end
    function tab:Subcategory(name, iconName)
        local index=#self.Subcategories+1
        local item=create("TextButton",{Name="Subcategory_"..name,Text="",AutoButtonColor=false,BackgroundColor3=T.Surface3,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,0,0,SUB_HEIGHT),Visible=false,ClipsDescendants=true,LayoutOrder=self.Button.LayoutOrder+index})
        item.Parent=self.Library.TabList; addRound(item,8)
        local image=icon(item,iconName or "menu",20,T.Muted); image.Position=UDim2.fromOffset(28,9)
        local title=label(item,name,16,Enum.Font.GothamBold,T.Muted); title.Position=UDim2.fromOffset(60,0); title.Size=UDim2.new(1,-60,1,0)
        local sub={Button=item,Title=title,Icon=image,Name=name,Tweens={}}
        table.insert(self.Subcategories,sub)
        connect(item.MouseButton1Click,function() self:ActivateSubcategory(sub) end)
        if self.Library.ActiveTab == self then

            if not self.ActiveSub then self.ActiveSub = sub end
            setSubState(sub,true,sub==self.ActiveSub)
            self:ApplyFilter()
        else
            setSubState(sub,false,false)
        end
        return sub
    end
    connect(button.MouseButton1Click, function() tab:Select() end)
    connect(button.MouseEnter, function() if self.ActiveTab ~= tab then tween(button, .12, {BackgroundTransparency = .7}) end end)
    connect(button.MouseLeave, function() if self.ActiveTab ~= tab then tween(button, .12, {BackgroundTransparency = 1}) end end)
    if not self.ActiveTab and not options.Hidden then tab:Select() end
    return tab
end

function Library:SelectTab(name)
    for _, tab in ipairs(self.Tabs) do if tab.Name == name then tab:Select(); return tab end end
end

local marqueeLabels = {}
local MARQUEE_SPEED, MARQUEE_PAUSE = 28, 1.2
local function marquee(textLabel)
    task.defer(function()
        local parent = textLabel.Parent
        if not parent then return end
        local holder = create("Frame", {Name = "Marquee", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
            AnchorPoint = textLabel.AnchorPoint, Position = textLabel.Position, Size = textLabel.Size, ZIndex = textLabel.ZIndex, LayoutOrder = textLabel.LayoutOrder})
        holder.Parent = parent
        textLabel.Parent = holder
        textLabel.AnchorPoint = Vector2.zero
        textLabel.Position = UDim2.new()
        textLabel.Size = UDim2.fromScale(1, 1)
        textLabel.TextTruncate = Enum.TextTruncate.None
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        table.insert(marqueeLabels, {Holder = holder, Label = textLabel, Start = os.clock()})
    end)
end
RunService.RenderStepped:Connect(function()
    local now = os.clock()
    for i = #marqueeLabels, 1, -1 do
        local m = marqueeLabels[i]
        local holder, textLabel = m.Holder, m.Label
        if not holder.Parent then
            table.remove(marqueeLabels, i)
        elseif holder.AbsoluteSize.X > 0 and textLabel.Visible then
            local width, textWidth = holder.AbsoluteSize.X, textLabel.TextBounds.X
            local overflow = textWidth - width
            if overflow > 1 then
                if textLabel.Size.X.Scale ~= 0 or textLabel.Size.X.Offset ~= math.ceil(textWidth) then
                    textLabel.Size = UDim2.new(0, math.ceil(textWidth), 1, 0)
                end
                local slide = overflow / MARQUEE_SPEED
                local cycle = (slide + MARQUEE_PAUSE) * 2
                local u = (now - m.Start) % cycle
                local x
                if u < MARQUEE_PAUSE then x = 0
                elseif u < MARQUEE_PAUSE + slide then x = (u - MARQUEE_PAUSE) * MARQUEE_SPEED
                elseif u < MARQUEE_PAUSE * 2 + slide then x = overflow
                else x = overflow - (u - MARQUEE_PAUSE * 2 - slide) * MARQUEE_SPEED end
                textLabel.Position = UDim2.fromOffset(-math.floor(x + .5), 0)
            elseif textLabel.Position.X.Offset ~= 0 or textLabel.Size.X.Scale ~= 1 then
                textLabel.Position = UDim2.new()
                textLabel.Size = UDim2.fromScale(1, 1)
                m.Start = now
            end
        end
    end
end)

local function newRow(card, height, name)
    local row = create("Frame", {Name = name or "Control", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height or 34)})
    row.Parent = card.Body
    return row
end

local function registerConfig(card, control, kind, name)
    local library = card.Tab.Library
    library.ConfigControls = library.ConfigControls or {}
    local base = table.concat({tostring(card.Tab.Name or "?"), tostring(card.Subcategory or ""), tostring(card.Title or "?"), tostring(name or kind)}, "/")
    library.ConfigIds = library.ConfigIds or {}
    local id, n = base, 1
    while library.ConfigIds[id] do n += 1; id = base .. "#" .. n end
    library.ConfigIds[id] = true
    table.insert(library.ConfigControls, {Id = id, Kind = kind, Control = control})
end

local function createCard(tab, options)
    options = type(options) == "string" and {Title = options} or (options or {})
    local card = {Tab = tab, SearchText = (options.Title or "Function") .. " ", Controls = {}, Subcategory = options.Subcategory, Title = options.Title or "Function", NoBinds = options.NoBinds == true}
    local frame = create("Frame", {BackgroundColor3 = T.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 43), AutomaticSize = Enum.AutomaticSize.Y})
    local side = string.lower(options.Side or ((#tab.Cards % 2 == 0) and "left" or "right"))
    frame.Parent = side == "right" and tab.Right or tab.Left; oneCornerCard(frame, 15)
    frame.Visible = subcategoryMatches(tab, options.Subcategory)
    frame.BackgroundTransparency = .08
    stroke(frame, Color3.fromRGB(68, 69, 73), 1, .35)
    local header = create("Frame", {BackgroundColor3 = T.BackgroundStart, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 43), ZIndex = 2})
    header.Parent = frame; header.BackgroundTransparency = .03
    oneCornerCard(header, 10)
    stroke(header, Color3.fromRGB(72, 73, 77), 1, .55)

    local collapseReserve = 26
    local title = label(header, options.Title or "Function", 19, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(12, 0); title.Size = UDim2.new(1, -(collapseReserve + (options.Keybind and 205 or 60)), 1, 0); title.ZIndex = 3
    if options.Risky then
        local risky = label(header, "!  Risky", 14, Enum.Font.GothamBold, T.Warning, Enum.TextXAlignment.Right)
        risky.Position = UDim2.new(1, -(collapseReserve + (options.Keybind and 200 or 130)), 0, 0); risky.Size = UDim2.fromOffset(90, 43); risky.ZIndex = 3
    end
    if options.Keybind then
        local state = options.Default ~= false
        local stateButton = create("TextButton", {Text="", AutoButtonColor=false, BackgroundColor3=state and T.Success or T.Error, BorderSizePixel=0, Position=UDim2.new(1,-(collapseReserve+31),0,11), Size=UDim2.fromOffset(21,21), ZIndex=5}); stateButton.Parent=header; addRound(stateButton,11)
        local bindButton = create("TextButton", {Text=options.BindName or "...", TextColor3=T.Muted, TextSize=12, Font=Enum.Font.GothamBold, AutoButtonColor=false, BackgroundColor3=T.Surface3, BorderSizePixel=0, Position=UDim2.new(1,-(collapseReserve+93),0,10), Size=UDim2.fromOffset(54,23), ZIndex=5}); bindButton.Parent=header; addRound(bindButton,6)
        connect(stateButton.MouseButton1Click,function() state=not state; tween(stateButton,.15,{BackgroundColor3=state and T.Success or T.Error}); safeCallback(options.ToggleCallback,state) end)
        connect(bindButton.MouseButton1Click,function() bindButton.Text="..."; local input=UserInputService.InputBegan:Wait(); local chosen=input.KeyCode~=Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType; bindButton.Text=chosen.Name; safeCallback(options.BindChanged,chosen) end)
        card.StateButton, card.BindButton = stateButton, bindButton
    end
    local body = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 43), Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y})
    body.Parent = frame; padding(body, 12, 12, 7, 9)
    local layout = create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    layout.Parent = body

    local collapseButton = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -2, .5, 0), Size = UDim2.fromOffset(24, 24), ZIndex = 5})
    collapseButton.Parent = header
    local collapseIcon = icon(collapseButton, "chevrons-up-down", 15, T.Muted); collapseIcon.AnchorPoint = Vector2.new(.5, .5); collapseIcon.Position = UDim2.fromScale(.5, .5); collapseIcon.ZIndex = 6
    local collapsed = false
    local animation = 0

    local function setBodyCollapsed(value)
        collapsed = value == true
        animation += 1
        local token = animation
        local startHeight = frame.AbsoluteSize.Y
        frame.AutomaticSize = Enum.AutomaticSize.None
        frame.ClipsDescendants = true
        frame.Size = UDim2.new(1, 0, 0, startHeight)
        body.Visible = true
        local target = collapsed and 43 or (43 + layout.AbsoluteContentSize.Y + 16)
        tween(frame, .22, {Size = UDim2.new(1, 0, 0, target)}, Enum.EasingStyle.Quint)
        tween(collapseIcon, .22, {Rotation = collapsed and 180 or 0}, Enum.EasingStyle.Quint)
        task.delay(.24, function()
            if token ~= animation then return end
            body.Visible = not collapsed
            frame.ClipsDescendants = false
            frame.Size = UDim2.new(1, 0, 0, 43)
            frame.AutomaticSize = Enum.AutomaticSize.Y
        end)
    end
    connect(collapseButton.MouseButton1Click, function() setBodyCollapsed(not collapsed) end)

    card.Frame, card.Header, card.Body, card.Layout, card.CollapseButton = frame, header, body, layout, collapseButton
    function card:SetCollapsed(value) setBodyCollapsed(value) end
    function card:IsCollapsed() return collapsed end
    table.insert(tab.Cards, card)
    return card
end

function Library:Card(tab, options) return createCard(tab, options) end
function Library:Section(tab, options) return createCard(tab, options) end

function Library:ESPPreview(tab, options)
    options=options or {}
    local card=createCard(tab,{Title=options.Title or "ESP Preview",Side=options.Side or "left"})
    local preview=create("Frame",{BackgroundColor3=Color3.fromRGB(13,12,27),BorderSizePixel=0,Size=UDim2.new(1,0,0,220)}); preview.Parent=card.Body; addRound(preview,9); stroke(preview,T.Accent,1,.55)
    local caption=label(preview,"PREVIEW",12,Enum.Font.BuilderSansExtraBold,T.Muted,Enum.TextXAlignment.Center); caption.Position=UDim2.fromOffset(0,8); caption.Size=UDim2.new(1,0,0,18)
    local viewport=create("ViewportFrame",{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(0,25),Size=UDim2.new(1,0,1,-25),Ambient=Color3.fromRGB(170,160,220),LightColor=Color3.fromRGB(255,255,255),LightDirection=Vector3.new(-1,-1,-1)}); viewport.Parent=preview
    local world=Instance.new("WorldModel"); world.Parent=viewport
    local camera=Instance.new("Camera"); camera.Parent=viewport; viewport.CurrentCamera=camera
    task.spawn(function()
        local ok,description=pcall(function() return Players:GetHumanoidDescriptionFromUserId((LocalPlayer and LocalPlayer.UserId) or 1) end)
        if not ok then return end
        local made,rig=pcall(function() return Players:CreateHumanoidModelFromDescription(description,Enum.HumanoidRigType.R6) end)
        if made and rig then
            rig.Parent=world
            local root=rig:FindFirstChild("HumanoidRootPart")
            if root then root.CFrame=CFrame.new(0,-2,0); camera.CFrame=CFrame.new(0,1.6,7)*CFrame.Angles(0,math.rad(180),0) end
        end
    end)
    return card
end

local ToggleOnColor = Color3.fromRGB(58, 137, 255)
local ToggleOffColor = Color3.fromRGB(58, 59, 64)
local ToggleKnobColor = Color3.fromRGB(240, 241, 245)

local function attachValueBindButton(library, row, control, xOffset, labelText)
    control.Binds = control.Binds or {}
    local button = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 29), Position = UDim2.new(1, xOffset, 0, 0)})
    button.Parent = row
    local buttonIcon = icon(button, "keyboard", 15, T.Muted)
    markAccent(buttonIcon, "ImageColor3")

    local hovering, popupOpen = false, false
    local function refreshBindVisibility()
        local show = hovering or popupOpen or #control.Binds > 0
        tween(buttonIcon, .12, {ImageTransparency = show and 0 or 1})
        button.Active = show
        if control.OnBindShown then control.OnBindShown(show) end
    end
    buttonIcon.ImageTransparency = 1
    connect(row.MouseEnter, function() hovering = true; refreshBindVisibility() end)
    connect(row.MouseLeave, function() hovering = false; refreshBindVisibility() end)
    buttonIcon.AnchorPoint = Vector2.new(.5, .5); buttonIcon.Position = UDim2.fromScale(.5, .5)

    local popup = create("Frame", {BackgroundColor3 = Color3.fromRGB(22, 23, 27), BackgroundTransparency = .03, BorderSizePixel = 0, Size = UDim2.fromOffset(236, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 520})
    popup.Parent = library.Gui
    addRound(popup, 10); padding(popup, 10, 10, 10, 10)
    local popupLayout = create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
    popupLayout.Parent = popup

    local title = label(popup, "Bind: " .. tostring(labelText or "Value"), 13, Enum.Font.GothamBold)
    title.Size = UDim2.new(1, 0, 0, 16); title.LayoutOrder = 1; title.ZIndex = 521

    local rowsHolder = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 521})
    rowsHolder.Parent = popup
    local rowsLayout = create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    rowsLayout.Parent = rowsHolder

    local addButton = create("TextButton", {Text = "+ Add Bind", TextColor3 = T.Muted, TextSize = 13, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, ZIndex = 521})
    addButton.Parent = popup; addRound(addButton, 6)

    local entries = {}
    local modes = {"Toggle", "Hold", "Always"}

    local hudName = tostring(labelText or "Value")
    local function syncHud()
        local hud = library.KeybindHUDInstance
        if not hud then return end
        local keys = {}
        for _, b in ipairs(control.Binds) do
            if b.Key and b.Mode ~= "Always" then table.insert(keys, b.Key.Name) end
        end
        if #keys == 0 then
            if hud.Rows[hudName] then hud:Remove(hudName) end
            return
        end
        local text = table.concat(keys, "/")
        if hud.Rows[hudName] then hud:SetKey(hudName, text) else hud:Add(hudName, text) end
        hud:SetActive(hudName, control.Value == true)
    end
    control.SyncBindHud = syncHud

    local function refreshTint()
        buttonIcon.ImageColor3 = (#control.Binds > 0) and T.Accent or T.Muted
        refreshBindVisibility()
        syncHud()
    end

    local function restoreIfActive(data)
        if data.Mode == "Always" and data.Active then
            data.Active = false
            control:Set(data.PriorValue)
        end
        if data.Mode == "Hold" and data.HoldActive then
            data.HoldActive = false
            control:Set(data.PriorValue)
        end
    end

    local function removeEntry(entry)
        restoreIfActive(entry.Data)
        for i, b in ipairs(control.Binds) do if b == entry.Data then table.remove(control.Binds, i) break end end
        for i, e in ipairs(entries) do if e == entry then table.remove(entries, i) break end end
        entry.Row:Destroy()
        refreshTint()
    end

    local function addEntry(preset)
        local data = {Mode = "Toggle", Key = nil, Value = true, HoldActive = false, PriorValue = nil, Active = false}
        table.insert(control.Binds, data)

        local bindRow = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), ZIndex = 522})
        bindRow.Parent = rowsHolder
        local bindLayout = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
        bindLayout.Parent = bindRow

        local keyButton = create("TextButton", {Text = "...", TextColor3 = T.Text, TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.fromOffset(56, 26), LayoutOrder = 1, ZIndex = 523})
        keyButton.Parent = bindRow; addRound(keyButton, 6)
        local modeButton = create("TextButton", {Text = "Toggle", TextColor3 = T.Text, TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.fromOffset(62, 26), LayoutOrder = 2, ZIndex = 523})
        modeButton.Parent = bindRow; addRound(modeButton, 6)
        local valueButton = create("TextButton", {Text = "On", TextColor3 = T.Text, TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.fromOffset(42, 26), LayoutOrder = 3, Visible = false, ZIndex = 523})
        valueButton.Parent = bindRow; addRound(valueButton, 6)
        local removeButton = create("TextButton", {Text = "x", TextColor3 = T.Muted, TextSize = 14, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 26), LayoutOrder = 4, ZIndex = 523})
        removeButton.Parent = bindRow

        local entry = {Row = bindRow, Data = data}
        table.insert(entries, entry)

        connect(keyButton.MouseButton1Click, function()
            keyButton.Text = "..."
            local input = UserInputService.InputBegan:Wait()
            local chosen = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
            data.Key = chosen
            keyButton.Text = chosen.Name
            syncHud()
        end)
        connect(modeButton.MouseButton1Click, function()
            restoreIfActive(data)
            local idx = (table.find(modes, data.Mode) or 1) % #modes + 1
            data.Mode = modes[idx]
            modeButton.Text = data.Mode
            syncHud()
            valueButton.Visible = data.Mode ~= "Toggle"
            keyButton.Visible = data.Mode ~= "Always"
            if data.Mode == "Always" then
                data.PriorValue = control.Value
                data.Active = true
                control:Set(data.Value)
            end
        end)
        connect(valueButton.MouseButton1Click, function()
            data.Value = not data.Value
            valueButton.Text = data.Value and "On" or "Off"
            if data.Mode == "Always" and data.Active then control:Set(data.Value) end
        end)
        connect(removeButton.MouseButton1Click, function() removeEntry(entry) end)
        if preset then
            data.Key = preset.Key
            keyButton.Text = preset.Key and preset.Key.Name or "..."
            data.Value = preset.Value ~= false
            valueButton.Text = data.Value and "On" or "Off"
            data.Mode = table.find(modes, preset.Mode) and preset.Mode or "Toggle"
            modeButton.Text = data.Mode
            valueButton.Visible = data.Mode ~= "Toggle"
            keyButton.Visible = data.Mode ~= "Always"
            if data.Mode == "Always" then
                data.PriorValue = control.Value
                data.Active = true
                control:Set(data.Value)
            end
        end
        refreshTint()
    end

    function control:GetBinds()
        local list = {}
        for _, b in ipairs(control.Binds) do
            table.insert(list, {Key = b.Key and b.Key.Name or nil, KeyType = b.Key and tostring(b.Key.EnumType) or nil, Mode = b.Mode, Value = b.Value})
        end
        return list
    end
    function control:SetBinds(list)
        for i = #entries, 1, -1 do removeEntry(entries[i]) end
        for _, b in ipairs(type(list) == "table" and list or {}) do
            if #entries >= 4 then break end
            local keyItem = nil
            if b.Key then
                local enumType = b.KeyType == "UserInputType" and Enum.UserInputType or Enum.KeyCode
                pcall(function() keyItem = enumType[b.Key] end)
            end
            addEntry({Key = keyItem, Mode = b.Mode, Value = b.Value})
        end
        refreshTint()
    end

    connect(addButton.MouseButton1Click, function()
        if #entries < 4 then addEntry() end
    end)

    local bindPopup = {Button = button, Popup = popup, Open = false}
    function bindPopup:Close()
        popup.Visible = false; self.Open = false
        popupOpen = false; refreshBindVisibility()
        if library.OpenBindPopup == self then library.OpenBindPopup = nil end
    end
    function bindPopup:OpenPopup()
        if library.OpenBindPopup and library.OpenBindPopup ~= self then library.OpenBindPopup:Close() end
        if library.OpenDropdown then library.OpenDropdown:Close() end
        if library.OpenColorPicker then library.OpenColorPicker:Close() end
        local p = button.AbsolutePosition - library.Gui.AbsolutePosition
        local viewW = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 1920
        local x = math.clamp(p.X - 205, 8, viewW - 236 - 8)
        popup.Position = UDim2.fromOffset(x, p.Y + button.AbsoluteSize.Y + 6)
        popup.Visible = true; self.Open = true; library.OpenBindPopup = self
        popupOpen = true; refreshBindVisibility()
    end
    connect(button.MouseButton1Click, function()
        if bindPopup.Open then bindPopup:Close() else bindPopup:OpenPopup() end
    end)

    table.insert(library.ValueBinds, {Control = control, Binds = control.Binds})
    return button
end

local attachColorPicker

local function createToggleControl(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local state = options.Default == true
    local row = newRow(card, 29, "Toggle")
    local bindable = options.Bindable ~= false and not card.NoBinds

    local cursor = 38
    local bindX, settingsX
    if bindable then cursor = cursor + 4; bindX = -(cursor + 26); cursor = cursor + 26 end
    if options.Settings then cursor = cursor + 2; settingsX = -(cursor + 28); cursor = cursor + 28 end

    local swatchRights = {}
    for i = 1, #(options.Colors or {}) do cursor = cursor + 5; swatchRights[i] = cursor; cursor = cursor + 22 end
    local text = label(row, options.Name or "Toggle", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -(cursor + 14), 1, 0); marquee(text)
    if options.Settings then
        local settingsButton = create("TextButton", {Text="⋯", TextColor3=T.Muted, TextSize=20, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.fromOffset(28,29), Position=UDim2.new(1,settingsX,0,0), AutoButtonColor=false})
        settingsButton.Parent = row
        connect(settingsButton.MouseButton1Click, function() safeCallback(options.Settings, row) end)
    end

    local track = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = state and ToggleOnColor or ToggleOffColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.fromOffset(38, 22)})
    track.Parent = row; addRound(track, 11); track:SetAttribute("RW_NoAccent", true)
    local knob = create("Frame", {BackgroundColor3 = ToggleKnobColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, .5), Position = state and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(16, 16)})
    knob.Parent = track; addRound(knob, 8)
    local control = {Row = row, Value = state, Binds = {}, Colors = {}}
    for i, color in ipairs(options.Colors or {}) do
        control.Colors[i] = attachColorPicker(card.Tab.Library, row, color, UDim2.new(1, -swatchRights[i], .5, 0), UDim2.fromOffset(22, 16))
    end
    if bindable then

        local shiftables = {}
        for i, colorControl in ipairs(control.Colors) do
            if colorControl.Swatch then table.insert(shiftables, {colorControl.Swatch, -swatchRights[i]}) end
        end
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") and child.Text == "⋯" then table.insert(shiftables, {child, settingsX}) end
        end
        control.OnBindShown = function(shown)
            for _, item in ipairs(shiftables) do
                local object, x = item[1], item[2]
                tween(object, .14, {Position = UDim2.new(1, x + (shown and 0 or 30), object.Position.Y.Scale, object.Position.Y.Offset)})
            end
        end
        attachValueBindButton(card.Tab.Library, row, control, bindX, options.Name)
        control.OnBindShown(#control.Binds > 0)
    end
    function control:Set(value, silent)
        state, self.Value = value == true, value == true
        local hud = card.Tab.Library.KeybindHUDInstance
        if hud and hud.Rows[tostring(options.Name or "Value")] then hud:SetActive(tostring(options.Name or "Value"), state) end
        tween(track, .16, {BackgroundColor3 = state and ToggleOnColor or ToggleOffColor})
        tween(knob, .16, {Position = state and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0)}, Enum.EasingStyle.Quad)
        if options.ShowInModuleList and card.Tab.Library.ModuleListControl then
            local modName = options.ModuleName or options.Name or "Toggle"
            if state then
                card.Tab.Library.ModuleListControl:Add(modName)
            else
                card.Tab.Library.ModuleListControl:Remove(modName)
            end
        end
        if not silent then
            if card.Tab.Library.SoundOnToggle then card.Tab.Library:PlayToggleSound() end
            safeCallback(options.Callback, state)
        end
    end
    connect(track.MouseButton1Click, function() control:Set(not state) end)
    card.SearchText ..= (options.Name or "Toggle") .. " "
    table.insert(card.Controls, control)
    registerConfig(card, control, "Toggle", options.Name or "Toggle")
    for i, colorControl in ipairs(control.Colors) do registerConfig(card, colorControl, "Color", (options.Name or "Toggle") .. " Color " .. i) end
    if options.ShowInModuleList and state and card.Tab.Library.ModuleListControl then
        card.Tab.Library.ModuleListControl:Add(options.ModuleName or options.Name or "Toggle")
    end
    if options.Flag then card.Tab.Library.Flags[options.Flag] = control end
    return control
end

function Library:Toggle(card, options) return createToggleControl(card, options) end

local function createCheckboxControl(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local state = options.Default == true
    local row = newRow(card, 29, "Checkbox")
    local bindable = options.Bindable ~= false and not card.NoBinds

    local cursor = 25
    local bindX, settingsX
    if bindable then cursor = cursor + 4; bindX = -(cursor + 26); cursor = cursor + 26 end
    if options.Settings then cursor = cursor + 2; settingsX = -(cursor + 28); cursor = cursor + 28 end
    local text = label(row, options.Name or "Checkbox", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -(cursor + 14), 1, 0); marquee(text)
    if options.Settings then
        local settingsButton = create("TextButton", {Text="⋯", TextColor3=T.Muted, TextSize=20, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.fromOffset(28,29), Position=UDim2.new(1,settingsX,0,0), AutoButtonColor=false})
        settingsButton.Parent = row
        connect(settingsButton.MouseButton1Click, function() safeCallback(options.Settings, row) end)
    end
    local box = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = state and T.AccentDark or T.Surface3, BorderSizePixel = 0, Position = UDim2.new(1, -25, .5, -11), Size = UDim2.fromOffset(23, 23)})
    box.Parent = row; addRound(box, 6); stroke(box, state and T.Accent or T.Muted, 1, .25)
    local check=icon(box,"check",15,T.Text); check.AnchorPoint=Vector2.new(.5,.5); check.Position=UDim2.fromScale(.5,.5); check.Visible=state
    local control = {Row = row, Value = state, Binds = {}}
    if bindable then attachValueBindButton(card.Tab.Library, row, control, bindX, options.Name) end
    function control:Set(value, silent)
        state, self.Value = value == true, value == true
        local hud = card.Tab.Library.KeybindHUDInstance
        if hud and hud.Rows[tostring(options.Name or "Value")] then hud:SetActive(tostring(options.Name or "Value"), state) end
        check.Visible = state
        tween(box, .15, {BackgroundColor3 = state and T.AccentDark or T.Surface3})
        if options.ShowInModuleList and card.Tab.Library.ModuleListControl then
            local modName = options.ModuleName or options.Name or "Checkbox"
            if state then
                card.Tab.Library.ModuleListControl:Add(modName)
            else
                card.Tab.Library.ModuleListControl:Remove(modName)
            end
        end
        if not silent then
            if card.Tab.Library.SoundOnToggle then card.Tab.Library:PlayToggleSound() end
            safeCallback(options.Callback, state)
        end
    end
    connect(box.MouseButton1Click, function() control:Set(not state) end)
    card.SearchText ..= (options.Name or "Checkbox") .. " "
    table.insert(card.Controls, control); registerConfig(card, control, "Toggle", options.Name or "Checkbox")
    if options.ShowInModuleList and state and card.Tab.Library.ModuleListControl then
        card.Tab.Library.ModuleListControl:Add(options.ModuleName or options.Name or "Checkbox")
    end
    if options.Flag then card.Tab.Library.Flags[options.Flag] = control end
    return control
end

function Library:Checkbox(card, options) return createCheckboxControl(card, options) end

local function createSlider(card, options)
    options = options or {}; local minimum, maximum = options.Min or 0, options.Max or 100
    local value = math.clamp(options.Default or minimum, minimum, maximum)
    local row = newRow(card, 48, "Slider")
    local text = label(row, options.Name or "Slider", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -70, 0, 23); marquee(text)

    local stepText = tostring(options.Step or 1)
    local decimals = string.find(stepText, "%.") and (#stepText - string.find(stepText, "%.")) or 0
    local function round(v) return tonumber(string.format("%." .. decimals .. "f", v)) or v end
    local function show(v) return string.format("%." .. decimals .. "f", v) end
    value = round(value)

    local valueText = create("TextBox", {Text = show(value) .. (options.Suffix or ""), ClearTextOnFocus = false, TextColor3 = T.Text, TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(1, -70, 0, 0), Size = UDim2.fromOffset(70, 23)})
    valueText.Parent = row
    local bar = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(150, 150, 162), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 9)})
    bar.Parent = row; addRound(bar, 5)
    local fill = create("Frame", {BackgroundColor3 = T.AccentDark, BorderSizePixel = 0, Size = UDim2.fromScale((value-minimum)/(maximum-minimum), 1)})
    fill.Parent = bar; addRound(fill, 5)
    local control = {Row = row, Value = value}
    function control:Set(newValue, silent)
        local step = options.Step or 1
        newValue = round(math.clamp(math.floor(((tonumber(newValue) or value) / step) + .5) * step, minimum, maximum))
        value, self.Value = newValue, newValue
        if not valueText:IsFocused() then valueText.Text = show(newValue) .. (options.Suffix or "") end
        tween(fill, .08, {Size = UDim2.fromScale((newValue-minimum)/(maximum-minimum), 1)})
        if not silent then safeCallback(options.Callback, newValue) end
    end
    connect(valueText.Focused, function() valueText.Text = show(value) end)
    connect(valueText.FocusLost, function()
        local typed = tonumber((string.gsub(string.gsub(valueText.Text, ",", "."), "[^%d%.%-]", "")))
        if typed then control:Set(typed) end
        valueText.Text = show(value) .. (options.Suffix or "")
    end)
    local sliding = false
    local function update(input)
        local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        control:Set(minimum + (maximum - minimum) * alpha)
    end
    connect(bar.InputBegan, function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = true; update(input) end end)
    connect(UserInputService.InputChanged, function(input) if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update(input) end end)
    connect(UserInputService.InputEnded, function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = false end end)
    card.SearchText ..= (options.Name or "Slider") .. " "; table.insert(card.Controls, control); registerConfig(card, control, "Value", options.Name or "Slider")
    if options.Flag then card.Tab.Library.Flags[options.Flag] = control end
    return control
end

function Library:Slider(card, options) return createSlider(card, options) end

local function createButton(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local row = newRow(card, 30, "Button")
    local background = create("Frame", {BackgroundColor3=options.Disabled and Color3.fromRGB(100,100,105) or T.AccentDark, BorderSizePixel=0, Size=UDim2.fromScale(1,1)}); background.Parent=row; addRound(background,6); gradient(background, background.BackgroundColor3, options.Disabled and Color3.fromRGB(140,140,142) or Color3.fromRGB(120,122,128),90)
    local button = create("TextButton", {Text = options.Name or "Click me!", TextColor3 = options.Disabled and T.Muted or T.Text, TextSize = 15, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundTransparency=1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex=background.ZIndex+1})
    button.Parent = background
    connect(button.MouseButton1Click, function() if not options.Disabled then tween(background, .07, {BackgroundColor3 = T.Accent}); task.delay(.08, function() tween(background, .12, {BackgroundColor3 = T.AccentDark}) end); safeCallback(options.Callback) end end)
    card.SearchText ..= (options.Name or "Button") .. " "; local control = {Row = row, Button = button}; table.insert(card.Controls, control); return control
end

function Library:Button(card, options) return createButton(card, options) end

local function createTextbox(card, options)
    options = options or {}; local row = newRow(card, 31, "Textbox")
    local text = label(row, options.Name or "TextBox", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(.42, 0, 1, 0); marquee(text)
    local box = create("TextBox", {Text = options.Default or "", PlaceholderText = options.Placeholder or "text...", PlaceholderColor3 = T.Muted, TextColor3 = T.Text, TextSize = 14, Font = Enum.Font.GothamMedium, ClearTextOnFocus = false, BackgroundColor3 = Color3.fromRGB(67,65,68), BorderSizePixel = 0, Position = UDim2.new(.42, 0, 0, 1), Size = UDim2.new(.58, 0, 1, -2)})
    box.Parent = row; addRound(box, 6); padding(box, 7, 7, 0, 0); stroke(box, T.Muted, 1, .45)
    local control = {Row = row, Value = box.Text}
    function control:Set(value, silent) box.Text = tostring(value); self.Value = box.Text; if not silent then safeCallback(options.Callback, box.Text) end end
    connect(box.FocusLost, function(enter) control.Value = box.Text; safeCallback(options.Callback, box.Text, enter) end)
    card.SearchText ..= (options.Name or "Textbox") .. " "; table.insert(card.Controls, control); registerConfig(card, control, "Value", options.Name or "Textbox"); if options.Flag then card.Tab.Library.Flags[options.Flag] = control end; return control
end

function Library:Textbox(card, options) return createTextbox(card, options) end

attachColorPicker = function(library, row, options, position, size)

    options=options or {}; local value=options.Default or T.Accent
    local h,s,v=value:ToHSV()
    local swatch=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=value,BorderSizePixel=0,AnchorPoint=Vector2.new(1,.5),Position=position,Size=size}); swatch.Parent=row; addRound(swatch,5); stroke(swatch,T.Text,1,.6); swatch:SetAttribute("RW_NoAccent",true)
    local W, PAD = 300, 12
    local inner = W - PAD * 2
    local popup=create("Frame",{BackgroundColor3=T.Surface2,BorderSizePixel=0,Size=UDim2.fromOffset(W,300),Visible=false,ZIndex=500}); popup.Parent=library.Gui; addRound(popup,12); stroke(popup,T.Accent,1,.3)
    popup:SetAttribute("RW_NoAccent",true)
    local drag=label(popup,options.Name or "Color Picker",15,Enum.Font.GothamBold); drag.Position=UDim2.fromOffset(PAD,4); drag.Size=UDim2.new(1,-PAD*2,0,28); drag.ZIndex=501; drag.Active=true; dragify(drag,popup)

    local sv=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=Color3.fromHSV(h,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(PAD,36),Size=UDim2.fromOffset(inner,176),ZIndex=501}); sv.Parent=popup; addRound(sv,6); stroke(sv,Color3.fromRGB(190,190,195),1,.4)
    local white=create("Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=502}); white.Parent=sv; addRound(white,6)
    create("UIGradient",{Color=ColorSequence.new(Color3.new(1,1,1),Color3.new(1,1,1)),Transparency=NumberSequence.new(0,1)}).Parent=white
    local black=create("Frame",{BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=503}); black.Parent=sv; addRound(black,6)
    create("UIGradient",{Rotation=90,Color=ColorSequence.new(Color3.new(0,0,0),Color3.new(0,0,0)),Transparency=NumberSequence.new(1,0)}).Parent=black
    local svMarker=create("Frame",{BackgroundColor3=value,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(s,0,1-v,0),Size=UDim2.fromOffset(18,18),ZIndex=504}); svMarker.Parent=sv; addRound(svMarker,9); stroke(svMarker,Color3.fromRGB(40,40,45),2,0)

    local hue=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(PAD,224),Size=UDim2.fromOffset(inner,14),ZIndex=501}); hue.Parent=popup; addRound(hue,7)
    create("UIGradient",{Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHSV(0,1,1)),ColorSequenceKeypoint.new(.17,Color3.fromHSV(.17,1,1)),ColorSequenceKeypoint.new(.33,Color3.fromHSV(.33,1,1)),ColorSequenceKeypoint.new(.5,Color3.fromHSV(.5,1,1)),ColorSequenceKeypoint.new(.67,Color3.fromHSV(.67,1,1)),ColorSequenceKeypoint.new(.83,Color3.fromHSV(.83,1,1)),ColorSequenceKeypoint.new(1,Color3.fromHSV(1,1,1))})}).Parent=hue
    local hueMarker=create("Frame",{BackgroundColor3=Color3.fromHSV(h,1,1),BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(h,0,.5,0),Size=UDim2.fromOffset(22,22),ZIndex=504}); hueMarker.Parent=hue; addRound(hueMarker,11); stroke(hueMarker,Color3.fromRGB(40,40,45),2,0)

    local function field(x, width, font)
        local box=create("TextBox",{Text="",ClearTextOnFocus=false,TextColor3=T.Text,TextSize=14,Font=font,BackgroundColor3=T.Surface3,BorderSizePixel=0,Position=UDim2.fromOffset(x,254),Size=UDim2.fromOffset(width,32),ZIndex=501}); box.Parent=popup; addRound(box,6); stroke(box,Color3.fromRGB(120,122,128),1,.5)
        return box
    end
    local channelW = 52
    local hexW = inner - channelW * 3 - 8 * 3
    local hex=field(PAD,hexW,Enum.Font.Code)
    local channels={}
    for i=1,3 do channels[i]=field(PAD+hexW+8+(i-1)*(channelW+8),channelW,Enum.Font.GothamMedium) end

    local control={Row=row,Value=value,Swatch=swatch,Popup=popup,Open=false}
    function control:Set(color,silent,keepHue)
        if typeof(color)~="Color3" then return end
        value,self.Value=color,color

        local nh,ns,nv=color:ToHSV()
        if keepHue then h=keepHue elseif ns>0.02 then h=nh end
        s,v=ns,nv
        swatch.BackgroundColor3=color; sv.BackgroundColor3=Color3.fromHSV(h,1,1)
        svMarker.Position=UDim2.new(s,0,1-v,0); svMarker.BackgroundColor3=color
        hueMarker.Position=UDim2.new(h,0,.5,0); hueMarker.BackgroundColor3=Color3.fromHSV(h,1,1)
        local r,g,b=math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5)
        hex.Text=string.format("#%02X%02X%02X",r,g,b)
        channels[1].Text,channels[2].Text,channels[3].Text=tostring(r),tostring(g),tostring(b)
        if not silent then safeCallback(options.Callback,color) end
    end
    function control:Close() popup.Visible=false; self.Open=false; if library.OpenColorPicker==self then library.OpenColorPicker=nil end end
    function control:OpenPopup()
        if library.OpenColorPicker and library.OpenColorPicker~=self then library.OpenColorPicker:Close() end
        if library.OpenDropdown then library.OpenDropdown:Close() end
        local p=swatch.AbsolutePosition-library.Gui.AbsolutePosition
        local view=library.Gui.AbsoluteSize
        local x=math.clamp(p.X-W+swatch.AbsoluteSize.X,8,math.max(8,view.X-W-8))
        local y=p.Y+swatch.AbsoluteSize.Y+6
        if y+300>view.Y-8 then y=math.max(8,p.Y-300-6) end
        popup.Position=UDim2.fromOffset(x,y); popup.Visible=true; self.Open=true; library.OpenColorPicker=self
    end
    local mode
    local function pick(input)
        if mode=="sv" then
            s=math.clamp((input.Position.X-sv.AbsolutePosition.X)/sv.AbsoluteSize.X,0,1)
            v=1-math.clamp((input.Position.Y-sv.AbsolutePosition.Y)/sv.AbsoluteSize.Y,0,1)
        else
            h=math.clamp((input.Position.X-hue.AbsolutePosition.X)/hue.AbsoluteSize.X,0,1)
        end
        control:Set(Color3.fromHSV(h,s,v),false,h)
    end
    connect(sv.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then mode="sv"; pick(input) end end)
    connect(hue.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then mode="hue"; pick(input) end end)
    connect(UserInputService.InputChanged,function(input) if mode and input.UserInputType==Enum.UserInputType.MouseMovement then pick(input) end end)
    connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then mode=nil end end)
    connect(hex.FocusLost,function() local raw=hex.Text:gsub("#",""); if #raw==6 then local n=tonumber(raw,16); if n then control:Set(Color3.fromRGB(math.floor(n/65536)%256,math.floor(n/256)%256,n%256)); return end end; control:Set(value,true) end)
    for i,box in ipairs(channels) do
        connect(box.FocusLost,function()
            local n=tonumber(box.Text)
            if not n then control:Set(value,true); return end
            local rgb={value.R*255,value.G*255,value.B*255}
            rgb[i]=math.clamp(math.floor(n+.5),0,255)
            control:Set(Color3.fromRGB(rgb[1],rgb[2],rgb[3]))
        end)
    end
    connect(swatch.MouseButton1Click,function() if control.Open then control:Close() else control:OpenPopup() end end)
    control:Set(value,true); return control
end

local function createColorPicker(card, options)
    options=options or {}
    local row=newRow(card,36,"ColorPicker")
    local text=label(row,options.Name or "Color",16,Enum.Font.GothamMedium); text.Size=UDim2.new(1,-48,1,0); marquee(text)
    local control=attachColorPicker(card.Tab.Library,row,options,UDim2.new(1,-3,.5,0),UDim2.fromOffset(31,29))
    card.SearchText ..=(options.Name or "Color").." "; table.insert(card.Controls,control); registerConfig(card,control,"Color",options.Name or "Color"); return control
end

function Library:ColorPicker(card,options) return createColorPicker(card,options) end

local INLINE_SWATCH_W, INLINE_SWATCH_H, INLINE_SWATCH_GAP = 22, 16, 5
local function createLabel(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local row = newRow(card, 29, "Label")
    local colors = options.Colors or {}
    local width = #colors * (INLINE_SWATCH_W + INLINE_SWATCH_GAP)
    local text = label(row, options.Name or "Label", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -(width + 8), 1, 0); marquee(text)
    local control = {Row = row, Colors = {}}
    for i, color in ipairs(colors) do
        local right = (i - 1) * (INLINE_SWATCH_W + INLINE_SWATCH_GAP)
        control.Colors[i] = attachColorPicker(card.Tab.Library, row, color, UDim2.new(1, -right, .5, 0), UDim2.fromOffset(INLINE_SWATCH_W, INLINE_SWATCH_H))
    end
    card.SearchText ..= (options.Name or "Label") .. " "
    table.insert(card.Controls, control)
    for i, colorControl in ipairs(control.Colors) do registerConfig(card, colorControl, "Color", (options.Name or "Label") .. " Color " .. i) end
    return control
end

function Library:Label(card, options) return createLabel(card, options) end

local GLOW_LAYERS, GLOW_STEP, GLOW_BASE, GLOW_FADE = 7, 2, .76, .03
local GLOW_COLOR = Color3.fromRGB(6, 6, 9)

local function hudBackdrop(library, frame, radius, zBase)
    zBase = zBase or frame.ZIndex
    local layers = {}
    for i = 1, GLOW_LAYERS do
        local pad = i * GLOW_STEP
        local base = GLOW_BASE + i * GLOW_FADE
        local layer = create("Frame", {Name = "Glow" .. i, BackgroundColor3 = GLOW_COLOR, BackgroundTransparency = base, BorderSizePixel = 0, ZIndex = math.max(1, zBase - i), Visible = false})
        layer.Parent = library.Gui
        addRound(layer, radius + pad)
        table.insert(layers, {Frame = layer, Pad = pad, Base = base})
    end
    local wasShown = false
    local lastShown, lastPos, lastSize, lastFade = nil, nil, nil, nil
    connect(RunService.RenderStepped, function()

        local shown = frame.Parent ~= nil and not frame:GetAttribute("RW_NoGlow")
        local node = frame
        while shown and node and node ~= library.Gui do
            if node:IsA("GuiObject") and not node.Visible then shown = false end
            node = node.Parent
        end
        if not shown and not wasShown then return end
        wasShown = shown

        local pos, size = frame.AbsolutePosition - library.Gui.AbsolutePosition, frame.AbsoluteSize
        local fade = frame:IsA("CanvasGroup") and frame.GroupTransparency or 0
        -- nothing changed since the last frame: writing the same values again still costs a layout pass
        if shown == lastShown and pos == lastPos and size == lastSize and fade == lastFade then return end
        lastShown, lastPos, lastSize, lastFade = shown, pos, size, fade
        for _, layer in ipairs(layers) do
            local p = layer.Pad
            layer.Frame.Visible = shown
            if shown then
                layer.Frame.Position = UDim2.fromOffset(pos.X - p, pos.Y - p)
                layer.Frame.Size = UDim2.fromOffset(size.X + p * 2, size.Y + p * 2)
                layer.Frame.BackgroundTransparency = layer.Base + (1 - layer.Base) * fade
            end
        end
    end)
    return layers
end

local function guiPosition(library, object)
    return object.AbsolutePosition - library.Gui.AbsolutePosition
end

local DROPDOWN_ITEM_H, DROPDOWN_PAD = 28, 4

local function createDropdown(card, options)
    options = options or {}
    local library = card.Tab.Library
    local values = options.Values or {}
    local multi = options.Multi == true
    local selected = multi and (options.Default or {}) or (options.Default or values[1])

    local row = newRow(card, 31, "Dropdown")
    local text = label(row, options.Name or "Dropdown", 16, Enum.Font.GothamMedium); marquee(text)
    text.Size = UDim2.new(.48, 0, 1, 0)

    local button = create("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(34, 36, 41), BorderSizePixel = 0,
        Position = UDim2.new(.48, 0, 0, 1), Size = UDim2.new(.52, 0, 1, -2), ZIndex = 5,
    })
    button.Parent = row; addRound(button, 6); stroke(button, Color3.fromRGB(255, 255, 255), 1, .9)

    local buttonText = label(button, "", 13, Enum.Font.GothamMedium, T.Text)
    buttonText.Size = UDim2.new(1, -30, 1, 0); buttonText.Position = UDim2.fromOffset(9, 0)
    buttonText.TextTruncate = Enum.TextTruncate.AtEnd; buttonText.ZIndex = 6
    local chevron = icon(button, "chevron-down", 13, T.Muted)
    chevron.AnchorPoint = Vector2.new(1, .5); chevron.Position = UDim2.new(1, -8, .5, 0); chevron.ZIndex = 6

    local menu = create("Frame", {
        Name = "DropdownMenu", BackgroundColor3 = Color3.fromRGB(18, 19, 23), BorderSizePixel = 0,
        Size = UDim2.fromOffset(160, 0), Visible = false, ZIndex = 450, ClipsDescendants = true,
    })
    menu.Parent = library.Gui
    addRound(menu, 8)
    hudBackdrop(library, menu, 8)
    local menuScroll = create("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2, ScrollBarImageColor3 = T.Muted, ScrollBarImageTransparency = .4, ZIndex = 451,
    })
    menuScroll.Parent = menu
    padding(menuScroll, DROPDOWN_PAD, DROPDOWN_PAD, DROPDOWN_PAD, DROPDOWN_PAD)

    local SEARCH_H = 26
    local searchBox = create("TextBox", {
        Text = "", PlaceholderText = "Search...", PlaceholderColor3 = T.Muted, ClearTextOnFocus = false,
        TextColor3 = T.Text, TextSize = 13, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Color3.fromRGB(30, 32, 37), BorderSizePixel = 0, Visible = false, ZIndex = 452,
        Position = UDim2.fromOffset(DROPDOWN_PAD, DROPDOWN_PAD), Size = UDim2.new(1, -DROPDOWN_PAD * 2, 0, SEARCH_H),
    })
    searchBox.Parent = menu; addRound(searchBox, 5); padding(searchBox, 8, 8, 0, 0)
    local query = ""
    local function searchable() return options.Search == true or (options.Search ~= false and #values > 5) end
    local menuLayout = create("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder})
    menuLayout.Parent = menuScroll

    local control = {Row = row, Button = button, Menu = menu, Value = selected, Open = false, Choices = {}}
    local BOX_OFF = Color3.fromRGB(40, 42, 48)

    local function selectedText()
        if not multi then return tostring(selected or "Select") end
        local list = {}
        for _, v in ipairs(values) do if selected[v] then table.insert(list, tostring(v)) end end
        if #list == 0 then return "None" end
        if #list <= 2 then return table.concat(list, ", ") end
        return list[1] .. ", " .. list[2] .. "  +" .. (#list - 2)
    end

    local function paintChoice(value, choice, instant)
        local isSel = (multi and selected[value] == true) or (not multi and selected == value)
        local t = instant and 0 or .12
        tween(choice.Text, t, {TextColor3 = isSel and T.Text or T.Muted})
        tween(choice.Mark, t, {ImageTransparency = isSel and 0 or 1})
        if choice.Box then tween(choice.Box, t, {BackgroundColor3 = isSel and T.Accent or BOX_OFF}) end
    end

    local function refreshChoices(instant)
        for value, choice in pairs(control.Choices) do paintChoice(value, choice, instant) end
        buttonText.Text = selectedText()
    end

    local function shownCount()
        local count = 0
        local q = string.lower(query)
        for value, choice in pairs(control.Choices) do
            local show = q == "" or string.find(string.lower(tostring(value)), q, 1, true) ~= nil
            choice.Button.Visible = show
            if show then count += 1 end
        end
        return count
    end

    local function menuHeight(count)
        local head = searchable() and (SEARCH_H + DROPDOWN_PAD) or 0
        return head + math.max(math.min(count, 7), 1) * (DROPDOWN_ITEM_H + 2) + DROPDOWN_PAD * 2
    end

    function control:Close()
        if not self.Open then return end
        self.Open = false
        menu.Visible = false
        tween(chevron, .12, {Rotation = 0})
        if library.OpenDropdown == self then library.OpenDropdown = nil end
    end

    function control:OpenPopup()
        if options.OnOpen then safeCallback(options.OnOpen, self) end
        if library.OpenDropdown and library.OpenDropdown ~= self then library.OpenDropdown:Close() end
        if library.OpenColorPicker then library.OpenColorPicker:Close() end
        if library.OpenBindPopup then library.OpenBindPopup:Close() end

        local p = guiPosition(library, button)
        local w = button.AbsoluteSize.X
        local withSearch = searchable()
        query = ""; searchBox.Text = ""
        searchBox.Visible = withSearch
        menuScroll.Position = UDim2.fromOffset(0, withSearch and (SEARCH_H + DROPDOWN_PAD) or 0)
        menuScroll.Size = UDim2.new(1, 0, 1, withSearch and -(SEARCH_H + DROPDOWN_PAD) or 0)
        local naturalH = menuHeight(shownCount())

        local viewH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 1080
        local below = p.Y + button.AbsoluteSize.Y + 4
        local openUp = (below + naturalH) > viewH - 8
        menu.Size = UDim2.fromOffset(w, 0)
        menu.Position = UDim2.fromOffset(p.X, openUp and (p.Y - 4) or below)
        menu.Visible = true
        local goal = {Size = UDim2.fromOffset(w, naturalH)}
        if openUp then goal.Position = UDim2.fromOffset(p.X, p.Y - naturalH - 4) end
        tween(menu, .14, goal, Enum.EasingStyle.Quint)
        tween(chevron, .12, {Rotation = 180})
        self.Open = true
        self._openUp, self._anchorY = openUp, p.Y
        library.OpenDropdown = self
    end

    connect(searchBox:GetPropertyChangedSignal("Text"), function()
        query = searchBox.Text
        if not control.Open then return end
        local h = menuHeight(shownCount())
        local w = menu.AbsoluteSize.X
        menu.Size = UDim2.fromOffset(w, h)
        if control._openUp then menu.Position = UDim2.fromOffset(menu.Position.X.Offset, control._anchorY - h - 4) end
        menuScroll.CanvasPosition = Vector2.zero
    end)

    function control:Set(value, silent)
        selected, self.Value = value, value
        refreshChoices()
        if not multi then self:Close() end
        if not silent then safeCallback(options.Callback, value) end
    end

    local function addChoice(value)
        local choice = {}
        local rowButton = create("TextButton", {
            Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, DROPDOWN_ITEM_H), ZIndex = 452,
        })
        rowButton.Parent = menuScroll; addRound(rowButton, 5)
        local textX = 9
        if multi then
            local box = create("Frame", {BackgroundColor3 = BOX_OFF, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 8, .5, 0), Size = UDim2.fromOffset(14, 14), ZIndex = 453})
            box.Parent = rowButton; addRound(box, 4)
            local mark = icon(box, "check", 10, Color3.fromRGB(18, 19, 23))
            mark.AnchorPoint = Vector2.new(.5, .5); mark.Position = UDim2.fromScale(.5, .5); mark.ZIndex = 454
            markAccent(box, "BackgroundColor3")
            choice.Box, choice.Mark = box, mark
            textX = 30
        else
            local mark = icon(rowButton, "check", 12, T.Accent)
            mark.AnchorPoint = Vector2.new(1, .5); mark.Position = UDim2.new(1, -8, .5, 0); mark.ZIndex = 453
            choice.Mark = mark
        end
        local text = label(rowButton, tostring(value), 13, Enum.Font.GothamMedium, T.Muted)
        text.Position = UDim2.fromOffset(textX, 0); text.Size = UDim2.new(1, -textX - 26, 1, 0)
        text.TextTruncate = Enum.TextTruncate.AtEnd; text.ZIndex = 453
        choice.Button, choice.Text = rowButton, text
        control.Choices[value] = choice
        connect(rowButton.MouseEnter, function() tween(rowButton, .1, {BackgroundTransparency = .94}) end)
        connect(rowButton.MouseLeave, function() tween(rowButton, .1, {BackgroundTransparency = 1}) end)
        connect(rowButton.MouseButton1Click, function()
            if multi then
                selected[value] = not selected[value]
                control:Set(selected)
            else
                control:Set(value)
            end
        end)
        paintChoice(value, choice, true)
    end
    for _, value in ipairs(values) do addChoice(value) end

    function control:SetValues(list)
        for _, choice in pairs(self.Choices) do choice.Button:Destroy() end
        table.clear(self.Choices)
        values = list or {}
        for _, value in ipairs(values) do addChoice(value) end
        if not multi and not table.find(values, selected) then
            selected = values[1]
            self.Value = selected
        end
        refreshChoices()
    end
    refreshChoices(true)
    connect(button.MouseButton1Click, function()
        if control.Open then control:Close() else control:OpenPopup() end
    end)

    card.SearchText ..= (options.Name or "Dropdown") .. " " .. table.concat(values, " ") .. " "
    registerConfig(card, control, "Value", options.Name or "Dropdown")
    table.insert(card.Controls, control)
    if options.Flag then library.Flags[options.Flag] = control end
    return control
end

function Library:Dropdown(card, options) return createDropdown(card, options) end

local function createKeybind(card, options)
    options = options or {}; local key = options.Default or Enum.KeyCode.Unknown
    local row = newRow(card, 31, "Keybind"); row.ZIndex = 4
    local text = label(row, options.Name or "Keybind", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -100, 1, 0); marquee(text)
    local button = create("TextButton", {Text = key.Name, TextColor3 = T.Text, TextSize = 14, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Position = UDim2.new(1, -96, 0, 1), Size = UDim2.fromOffset(96, 29)})
    button.Parent = row; addRound(button, 7)
    local control = {Row = row, Key = key, Callback = options.Callback, Held = false, HudVisible = options.ShowInHud ~= false}
    local name = options.Name or "Keybind"
    local function hud() return card.Tab.Library.KeybindHUDInstance end
    local function syncHud()
        local instance = hud()
        if not instance then return end
        instance:Remove(name)
        if control.HudVisible and key ~= Enum.KeyCode.Unknown then
            instance:Add(name, key.Name)
            if control.Held then instance:SetActive(name, true) end
        end
    end
    function control:SetHudVisible(visible)
        control.HudVisible = visible == true
        syncHud()
    end
    syncHud()
    connect(button.MouseButton1Click, function()
        button.Text = "..."
        local input = UserInputService.InputBegan:Wait()
        key = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
        control.Key = key; button.Text = key.Name
        syncHud()
        safeCallback(options.Changed, key)
    end)
    connect(UserInputService.InputBegan, function(input, processed)
        local pressed = input.KeyCode == control.Key or input.UserInputType == control.Key
        if pressed and not processed then
            control.Held = true
            if hud() and control.HudVisible then hud():SetActive(name, true) end
            safeCallback(options.Callback, true)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        local released = input.KeyCode == control.Key or input.UserInputType == control.Key
        if released then
            control.Held = false
            if hud() and control.HudVisible then hud():SetActive(name, false) end
            safeCallback(options.Callback, false)
        end
    end)
    function control:SetKey(newKey)
        if typeof(newKey) ~= "EnumItem" then return end
        key = newKey; control.Key = newKey; button.Text = newKey.Name
        syncHud()
        safeCallback(options.Changed, newKey)
    end
    table.insert(card.Tab.Library.Keybinds, control); card.SearchText ..= name .. " "; table.insert(card.Controls, control); registerConfig(card, control, "Key", name); return control
end

function Library:Keybind(card, options) return createKeybind(card, options) end

local function setHudStyle(frame, style)
    if not frame or typeof(frame)~="Instance" then return end
    if frame:IsA("TextLabel") or frame.Name=="Indicator" then frame.BackgroundTransparency=1; return end
    if frame.Name=="Watermark" then for _,child in ipairs(frame:GetChildren()) do if child.Name=="StyleTarget" then setHudStyle(child,style) end end; return end
    style=string.lower(style or "dark")
    for _,child in ipairs(frame:GetChildren()) do if child:IsA("UIGradient") then child:Destroy() end end
    if style=="glass" then frame.BackgroundTransparency=.16; frame.BackgroundColor3=Color3.fromRGB(94,90,112); gradient(frame,Color3.fromRGB(126,120,150),Color3.fromRGB(37,34,62),25); if not frame:FindFirstChildOfClass("UIStroke") then stroke(frame,T.Text,1,.75) end
    elseif style=="gradient" or style=="rarely" or style=="default" then frame.BackgroundTransparency=0; frame.BackgroundColor3=T.BackgroundStart; gradient(frame,T.BackgroundStart,T.BackgroundEnd,25)
    else frame.BackgroundTransparency=0; frame.BackgroundColor3=T.BackgroundStart; gradient(frame,T.BackgroundStart,T.BackgroundEnd,25) end
end

function Library:SetHUDStyle(frame, style)
    if type(frame)=="table" then frame=frame.Frame or frame.Instance end
    if frame and typeof(frame)=="Instance" and frame:IsA("GuiObject") then setHudStyle(frame,style) end
end

local HUD_MENU_TITLES = {Watermark = "Watermark", Keybinds = "Keybinds", Indicators = "Indicators", Crosshair = "Crosshair", ModuleList = "Module List", KeyStrokes = "KeyStrokes"}
local HUD_MENU_ICONS = {Watermark = "monitor", Keybinds = "keyboard", Indicators = "activity", Crosshair = "scan-eye", ModuleList = "list", KeyStrokes = "mouse-pointer-click"}
local WATERMARK_METRICS = {"FPS", "BPS", "TPS", "PING", "CPU", "RAM USAGE", "LOGIN"}

local function attachHudMenu(library, frame, options)
    options = options or {}
    table.insert(library.HUDRegistry, {Frame = frame, Type = options.Element or "HUD"})
    frame.Active = true
    local homePosition = frame.Position
    local ROW_H = 28
    local order = 0
    local function nextOrder() order += 1; return order end

    local menu = create("CanvasGroup", {Name = "HUDContextMenu", BackgroundColor3 = Color3.fromRGB(16, 17, 21), BackgroundTransparency = .02, BorderSizePixel = 0, Size = UDim2.fromOffset(212, 0), AutomaticSize = Enum.AutomaticSize.Y, GroupTransparency = 1, Visible = false, ZIndex = 700})
    menu.Parent = library.Gui; addRound(menu, 9)
    padding(menu, 6, 6, 6, 6)
    local list = create("UIListLayout", {Padding = UDim.new(0, 2), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
    list.Parent = menu
    hudBackdrop(library, menu, 9)

    local header = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder()})
    header.Parent = menu
    local headerIcon = icon(header, HUD_MENU_ICONS[options.Element] or "layout-dashboard", 14, T.Accent)
    headerIcon.Position = UDim2.fromOffset(8, 8)
    local headerTitle = label(header, HUD_MENU_TITLES[options.Element] or tostring(options.Element or "HUD element"), 13, Enum.Font.GothamBold, T.Text)
    headerTitle.Position = UDim2.fromOffset(30, 0); headerTitle.Size = UDim2.new(1, -36, 1, 0)

    local function divider()
        local line = create("Frame", {BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .92, BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 1), LayoutOrder = nextOrder()})
        line.Parent = menu
    end
    local function section(text)
        local caption = label(menu, string.upper(text), 10, Enum.Font.GothamBold, T.Muted)
        caption.Size = UDim2.new(1, 0, 0, 20); caption.LayoutOrder = nextOrder()
        padding(caption, 8, 8, 4, 0)
    end
    local function row(text, iconName)
        local b = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = nextOrder()})
        b.Parent = menu; addRound(b, 6)
        local x = 10
        if iconName then
            local image = icon(b, iconName, 14, T.Muted); image.Position = UDim2.fromOffset(9, (ROW_H - 14) / 2)
            x = 31
        end
        local text = label(b, text, 12, Enum.Font.GothamMedium, T.Text)
        text.Position = UDim2.fromOffset(x, 0); text.Size = UDim2.new(1, -x - 30, 1, 0)
        connect(b.MouseEnter, function() tween(b, .1, {BackgroundTransparency = .94}) end)
        connect(b.MouseLeave, function() tween(b, .1, {BackgroundTransparency = 1}) end)
        return b
    end
    local function checkRow(text, active, onToggle)
        local b = row(text)
        local box = create("Frame", {BackgroundColor3 = active and T.Accent or Color3.fromRGB(40, 42, 48), BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -9, .5, 0), Size = UDim2.fromOffset(14, 14)})
        markAccent(box, "BackgroundColor3")
        box.Parent = b; addRound(box, 4)
        local mark = icon(box, "check", 10, Color3.fromRGB(16, 17, 21))
        mark.AnchorPoint = Vector2.new(.5, .5); mark.Position = UDim2.fromScale(.5, .5); mark.ImageTransparency = active and 0 or 1
        connect(b.MouseButton1Click, function()
            active = not active
            tween(box, .12, {BackgroundColor3 = active and T.Accent or Color3.fromRGB(40, 42, 48)})
            tween(mark, .12, {ImageTransparency = active and 0 or 1})
            onToggle(active)
        end)
    end

    local function close()
        if not menu.Visible then return end
        menu.Visible = false
        menu.GroupTransparency = 1
        if library.OpenHUDMenu == menu then library.OpenHUDMenu = nil end
    end
    local function open()
        if library.OpenHUDMenu and library.OpenHUDMenu ~= menu then library.OpenHUDMenu.Visible = false end
        menu.Visible = true
        local view = workspace.CurrentCamera.ViewportSize
        local p, size = guiPosition(library, frame), menu.AbsoluteSize
        menu.Position = UDim2.fromOffset(math.clamp(p.X, 8, view.X - size.X - 8), math.clamp(p.Y + frame.AbsoluteSize.Y + 10, 8, view.Y - size.Y - 8))
        menu.GroupTransparency = 1
        tween(menu, .14, {GroupTransparency = 0})
        library.OpenHUDMenu = menu
    end

    if options.MenuExtra then
        options.MenuExtra({Divider = divider, Section = section, Row = row, CheckRow = checkRow, Close = close})
    end
    if options.Element == "Watermark" then
        divider()
        section("Metrics")
        for _, name in ipairs(WATERMARK_METRICS) do
            checkRow(name, options["Show" .. name] ~= false, function(active)
                options["Show" .. name] = active
                if options.WatermarkControl then options.WatermarkControl:SetStat(name, active) end
            end)
        end
    end
    divider()
    section("Actions")
    connect(row("Reset position", "locate-fixed").MouseButton1Click, function() frame.Position = homePosition; close() end)
    connect(row("Hide element", "eye-off").MouseButton1Click, function() frame.Visible = false; close() end)

    local function inside(object, pos)
        local a, s = object.AbsolutePosition, object.AbsoluteSize
        return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
    end
    connect(UserInputService.InputBegan, function(input)
        local kind = input.UserInputType
        if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 then return end
        local pos = Vector2.new(input.Position.X, input.Position.Y)
        local onFrame = frame.Visible and frame.Parent ~= nil and inside(frame, pos)
        if kind == Enum.UserInputType.MouseButton2 and onFrame then open(); return end
        if menu.Visible and not onFrame and not inside(menu, pos) then close() end
    end)
    return menu
end

local NOTIFY_PLACES = {
    ["Bottom Right"] = {Anchor = Vector2.new(1, 1), X = UDim.new(1, -22), Y = "bottom", V = "Bottom", H = "Right", Slide = UDim2.fromOffset(40, 0)},
    ["Bottom Left"] = {Anchor = Vector2.new(0, 1), X = UDim.new(0, 22), Y = "bottom", V = "Bottom", H = "Left", Slide = UDim2.fromOffset(-40, 0)},
    ["Bottom Center"] = {Anchor = Vector2.new(.5, 1), X = UDim.new(.5, 0), Y = "bottom", V = "Bottom", H = "Center", Slide = UDim2.fromOffset(0, 16)},
    ["Top Right"] = {Anchor = Vector2.new(1, 0), X = UDim.new(1, -22), Y = "top", V = "Top", H = "Right", Slide = UDim2.fromOffset(40, 0)},
    ["Top Left"] = {Anchor = Vector2.new(0, 0), X = UDim.new(0, 22), Y = "top", V = "Top", H = "Left", Slide = UDim2.fromOffset(-40, 0)},
    ["Top Center"] = {Anchor = Vector2.new(.5, 0), X = UDim.new(.5, 0), Y = "top", V = "Top", H = "Center", Slide = UDim2.fromOffset(0, -16)},
    ["Center"] = {Anchor = Vector2.new(.5, .5), X = UDim.new(.5, 0), Y = "center", V = "Center", H = "Center", Slide = UDim2.fromOffset(0, 16)},
}
Library.NotificationPositions = {"Bottom Right", "Bottom Left", "Bottom Center", "Top Right", "Top Left", "Top Center", "Center"}

function Library:_placeNotifications()
    local holder, layout = self.NotificationHolder, self.NotificationLayout
    if not (holder and layout) then return end
    local place = NOTIFY_PLACES[self.NotificationPosition or "Bottom Right"] or NOTIFY_PLACES["Bottom Right"]
    local y
    if place.Y == "bottom" then
        y = UDim.new(1, -22)
    elseif place.Y == "center" then
        y = UDim.new(.5, 0)
    else
        local top = 12
        pcall(function() top = GuiService:GetGuiInset().Y + 12 end)
        local mark = self.WatermarkInstance and self.WatermarkInstance.Frame
        if self.NotificationPosition == "Top Left" and mark and mark.Visible and mark.Parent then
            local origin = self.Gui.AbsolutePosition
            local p, size = mark.AbsolutePosition - origin, mark.AbsoluteSize
            if p.X < 460 and p.Y < 260 then top = math.max(top, p.Y + size.Y + 10) end
        end
        y = UDim.new(0, top)
    end
    holder.AnchorPoint = place.Anchor
    holder.Position = UDim2.new(place.X, y)
    layout.VerticalAlignment = Enum.VerticalAlignment[place.V]
    layout.HorizontalAlignment = Enum.HorizontalAlignment[place.H]
    self._notifySlide = place.Slide
end

function Library:Notify(options)
    options = type(options) == "string" and {Message = options} or (options or {})

    do
        if not self.NotificationHolder then
            local holder=create("Frame",{Name="Notifications",BackgroundTransparency=1,Size=UDim2.fromOffset(420,460)}); holder.Parent=self.Gui
            local layout=create("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder}); layout.Parent=holder
            self.NotificationHolder, self.NotificationLayout = holder, layout
            task.spawn(function() while holder.Parent do self:_placeNotifications(); task.wait(.5) end end)
        end
        self:_placeNotifications()
        local kind=string.lower(options.Type or "info")
        local colors={success=Color3.fromRGB(120,220,150),warning=Color3.fromRGB(240,200,110),error=Color3.fromRGB(240,105,125),info=T.Accent}
        local color=colors[kind] or colors.info
        local function hex(c) return string.format("#%02x%02x%02x",math.floor(c.R*255+.5),math.floor(c.G*255+.5),math.floor(c.B*255+.5)) end
        local function escape(text) return (string.gsub(string.gsub(string.gsub(tostring(text),"&","&amp;"),"<","&lt;"),">","&gt;")) end
        local titleText=options.Title or ({success="Success",warning="Warning",error="Error",info="Info"})[kind]
        local messageText=escape(options.Message or ({success="Function enabled.",warning="Please check this action.",error="An error occurred.",info="Information received."})[kind])
        messageText=string.gsub(messageText,"([%+%-]?%d[%d%.,]*)",'<font color="'..hex(color)..'">%1</font>')
        local rich=(options.Title==false) and messageText or ('<b><font color="'..hex(color)..'">'..escape(titleText)..'</font></b>  '..messageText)
        local HEIGHT=36
        local slot=create("Frame",{BackgroundTransparency=1,Size=UDim2.fromOffset(0,HEIGHT),AutomaticSize=Enum.AutomaticSize.X}); slot.Parent=self.NotificationHolder
        local pill=create("Frame",{Name="Notification",BackgroundColor3=Color3.fromRGB(12,13,16),BackgroundTransparency=.38,BorderSizePixel=0,Size=UDim2.fromOffset(0,HEIGHT),AutomaticSize=Enum.AutomaticSize.X,ZIndex=202}); pill.Parent=slot
        addRound(pill,HEIGHT/2); padding(pill,14,14,0,0)

        local glows={}
        for i=1,5 do
            local pad=i*3
            local layer=create("Frame",{Name="Glow"..i,BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=.82+i*.03,BorderSizePixel=0,Position=UDim2.fromOffset(-14-pad,-pad),Size=UDim2.new(1,28+pad*2,1,pad*2),ZIndex=201-i})
            layer.Parent=pill; addRound(layer,HEIGHT/2+pad); glows[i]=layer
        end

        local iconImage
        if options.Icon then

            iconImage=icon(pill,options.Icon,16,color); iconImage.ZIndex=203; iconImage.AnchorPoint=Vector2.new(0,.5); iconImage.Position=UDim2.new(0,0,.5,0); iconImage.ImageTransparency=1
        end
        local text=label(pill,rich,16,Enum.Font.GothamBold,Color3.fromRGB(236,238,242)); text.RichText=true; text.AutomaticSize=Enum.AutomaticSize.X; text.Size=UDim2.fromOffset(0,HEIGHT); text.ZIndex=203
        if iconImage then local shift=create("UIPadding",{PaddingLeft=UDim.new(0,24)}); shift.Parent=text end
        local textStroke=create("UIStroke",{Color=Color3.fromRGB(0,0,0),Transparency=.55,Thickness=1}); textStroke.Parent=text
        local all={pill,text}; for _,g in ipairs(glows) do table.insert(all,g) end
        local function fade(t,out)
            if iconImage then tween(iconImage,t,{ImageTransparency=out and 1 or 0}) end
            for _,o in ipairs(all) do
                if o==text then tween(o,t,{TextTransparency=out and 1 or 0}) ; tween(textStroke,t,{Transparency=out and 1 or .55})
                elseif o==pill then tween(o,t,{BackgroundTransparency=out and 1 or .38})
                else local i=tonumber(string.match(o.Name,"%d+")); tween(o,t,{BackgroundTransparency=out and 1 or (.82+i*.03)}) end
            end
        end
        for _,o in ipairs(all) do if o==text then o.TextTransparency=1; textStroke.Transparency=1 else o.BackgroundTransparency=1 end end
        local away=self._notifySlide or UDim2.fromOffset(40,0)
        pill.Position=away; tween(pill,.25,{Position=UDim2.fromOffset(0,0)},Enum.EasingStyle.Quint); fade(.2,false)
        local duration=options.Duration or 4
        task.delay(duration,function() if slot.Parent then fade(.3,true); tween(pill,.3,{Position=away},Enum.EasingStyle.Quint); task.wait(.32); slot:Destroy() end end)
        return pill
    end

end

-- Logo picture: downloaded once into RarelyWin/cache and loaded like a local file. Nil -> the "RW" text is used.
local WATERMARK_LOGO_URL = "https://raw.githubusercontent.com/RarelyWin/dev/refs/heads/main/RW.png"
local watermarkLogoAsset = nil
local function watermarkLogo()
    if watermarkLogoAsset ~= nil then return watermarkLogoAsset or nil end
    watermarkLogoAsset = false
    pcall(function()
        local path = CACHE_DIR .. "/RW.png"
        if not (isfile and isfile(path)) and writefile then
            ensureFolder(CACHE_DIR)
            writefile(path, game:HttpGet(WATERMARK_LOGO_URL))
        end
        if getcustomasset and isfile and isfile(path) then watermarkLogoAsset = getcustomasset(path) end
    end)
    return watermarkLogoAsset or nil
end

function Library:Watermark(options)
    options=options or {}; options.Element="Watermark"
    local defaults={"FPS","BPS","TPS","PING","CPU","RAM USAGE","LOGIN"}; local criteria=options.Criteria or defaults; local enabled=options.Enabled or {}
    for _,name in ipairs(defaults) do
        if enabled[name]==nil then enabled[name]=(name=="FPS" or name=="PING") end
        if options["Show"..name]==nil then options["Show"..name]=enabled[name] end
    end

    local BAR_HEIGHT = 30
    local TEXT_COLOR = Color3.fromRGB(226, 228, 233)

    local frame = create("Frame", {
        Name = "Watermark", BackgroundColor3 = Color3.fromRGB(15, 16, 19), BackgroundTransparency = .32,
        BorderSizePixel = 0, Position = options.Position or UDim2.fromOffset(20, 72),
        Size = UDim2.fromOffset(0, BAR_HEIGHT), AutomaticSize = Enum.AutomaticSize.X, Active = true, ZIndex = 200,
    })
    frame.Parent = self.Gui
    addRound(frame, BAR_HEIGHT / 2)
    hudBackdrop(self, frame, BAR_HEIGHT / 2)
    padding(frame, 12, 12, 0, 0)
    local barLayout = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder})
    barLayout.Parent = frame

    local logoCell = create("Frame", {Name = "Logo", BackgroundTransparency = 1, Size = UDim2.fromOffset(28, BAR_HEIGHT), LayoutOrder = 1, ZIndex = 201})
    logoCell.Parent = frame
    local logoAsset = watermarkLogo()
    if logoAsset then
        local logoImage = create("ImageLabel", {Name = "LogoImage", BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(26, 26), Image = logoAsset, ScaleType = Enum.ScaleType.Fit, ZIndex = 202})
        logoImage.Parent = logoCell
    else
        local logo = label(logoCell, "RW", 13, Enum.Font.GothamBlack, Color3.fromRGB(240, 242, 247), Enum.TextXAlignment.Center)
        logo.Size = UDim2.fromScale(1, 1); logo.ZIndex = 202
    end

    local afterLogoDivider = create("Frame", {BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .84, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 12), LayoutOrder = 2, ZIndex = 202})
    afterLogoDivider.Parent = frame

    local statIcons = {FPS = "monitor", BPS = "activity", TPS = "gauge", PING = "wifi", CPU = "cpu", ["RAM USAGE"] = "memory-stick", LOGIN = "user"}
    local cells = {}
    for index, name in ipairs(criteria) do
        local key = string.upper(name)

        local divider = create("Frame", {Name = key .. "_Divider", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .88, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 12), LayoutOrder = index * 10 + 1, Visible = false, ZIndex = 202})
        divider.Parent = frame
        local cell = create("Frame", {Name = key, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, BAR_HEIGHT), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = index * 10 + 2, Visible = false, ZIndex = 202})
        cell.Parent = frame
        local cellLayout = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
        cellLayout.Parent = cell
        local image = icon(cell, statIcons[key] or "circle", 11, T.Accent); image.LayoutOrder = 1; image.ZIndex = 203
        local value = label(cell, "", 12, Enum.Font.GothamMedium, TEXT_COLOR); value.AutomaticSize = Enum.AutomaticSize.X; value.Size = UDim2.fromOffset(0, BAR_HEIGHT); value.LayoutOrder = 2; value.ZIndex = 203
        cells[key] = {Cell = cell, Divider = divider, Icon = image, Text = value}
    end

    local orderList = {}
    for i, name in ipairs(criteria) do orderList[i] = string.upper(name) end
    local function applyOrder()
        for i, key in ipairs(orderList) do
            local entry = cells[key]
            if entry then entry.Cell.LayoutOrder = i * 10 + 2; entry.Divider.LayoutOrder = i * 10 + 1 end
        end
    end
    local function cellAt(point)
        for key, entry in pairs(cells) do
            local c = entry.Cell
            if c.Visible then
                local p, size = c.AbsolutePosition, c.AbsoluteSize
                if point.X >= p.X - 4 and point.X <= p.X + size.X + 4 then return key end
            end
        end
        return nil
    end
    local drag = nil
    connect(frame.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            drag = {Key = cellAt(input.Position), Start = input.Position, FramePosition = frame.Position}
        end
    end)
    local function reorderTo(x, key)
        local others = {}
        for _, k in ipairs(orderList) do
            if k ~= key and cells[k] and cells[k].Cell.Visible then table.insert(others, k) end
        end
        local slot = 1
        for i, k in ipairs(others) do
            local c = cells[k].Cell
            if x > c.AbsolutePosition.X + c.AbsoluteSize.X / 2 then slot = i + 1 end
        end
        local new = {}
        for i, k in ipairs(others) do
            if i == slot then table.insert(new, key) end
            table.insert(new, k)
        end
        if slot > #others then table.insert(new, key) end
        for _, k in ipairs(orderList) do if not table.find(new, k) then table.insert(new, k) end end
        orderList = new
        applyOrder()
    end
    connect(UserInputService.InputChanged, function(input)
        if not drag or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end
        local delta = input.Position - drag.Start
        if drag.Mode == nil then
            if drag.Key and math.abs(delta.X) > 4 and math.abs(delta.Y) < BAR_HEIGHT * 0.6 then
                drag.Mode = "reorder"
                cells[drag.Key].Text.TextTransparency = .45
            elseif (not drag.Key and delta.Magnitude > 2) or math.abs(delta.Y) >= BAR_HEIGHT * 0.6 then
                drag.Mode = "move"
            end
        elseif drag.Mode == "reorder" and math.abs(delta.Y) > BAR_HEIGHT * 1.1 then
            cells[drag.Key].Text.TextTransparency = 0
            drag.Mode = "move"
        end
        if drag.Mode == "reorder" then
            reorderTo(input.Position.X, drag.Key)
        elseif drag.Mode == "move" then
            local p = drag.FramePosition
            frame.Position = UDim2.new(p.X.Scale, p.X.Offset + delta.X, p.Y.Scale, p.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if drag and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            if drag.Key and cells[drag.Key] then cells[drag.Key].Text.TextTransparency = 0 end
            drag = nil
        end
    end)

    local watermark = {Frame = frame, Criteria = criteria, Enabled = enabled}
    function watermark:GetOrder() return table.clone(orderList) end
    function watermark:SetCriteria(list) if type(list) == "table" then criteria = list; self.Criteria = list end end
    function watermark:SetStat(name, value) enabled[string.upper(name)] = value == true end
    function watermark:SetCompact(value) self.Compact = value == true end
    options.WatermarkControl = watermark

    local started, frameCount, fps, lastTps = os.clock(), 0, 0, 0
    local nextText = 0
    connect(RunService.RenderStepped, function(dt)
        frameCount += 1
        if os.clock() - started >= .5 then
            fps = math.floor(frameCount / (os.clock() - started)); frameCount, started = 0, os.clock()
            lastTps = math.floor(1 / math.max(dt, .001) + .5)
        end
        -- the texts are rebuilt 4 times a second, and not at all while the watermark is hidden
        if not frame.Visible then return end
        local clockNow = os.clock()
        if clockNow < nextText then return end
        nextText = clockNow + .25
        local ping = math.floor((LocalPlayer and LocalPlayer:GetNetworkPing() or 0) * 1000)
        local values = {
            FPS = function() return fps .. " FPS" end,
            BPS = function() local r = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); return r and string.format("%.0f BPS", r.AssemblyLinearVelocity.Magnitude) or "0 BPS" end,
            TPS = function() return lastTps .. " TPS" end,
            PING = function() return ping .. " MS" end,
            CPU = function() return string.format("%.0f%% CPU", math.clamp((1 - dt / .0167) * 100, 0, 100)) end,
            ["RAM USAGE"] = function() local ok, v = pcall(function() return StatsService:GetTotalMemoryUsageMb() end); return ok and string.format("%.0f MB", v) or "-- MB" end,
            LOGIN = function() return "@" .. tostring(LocalPlayer and LocalPlayer.Name or "player") end,
        }
        local seenVisible = false
        for _, key in ipairs(orderList) do
            local entry = cells[key]
            if entry then
                local text = (enabled[key] and values[key]) and values[key]() or ""
                local visible = text ~= ""
                if entry.Cell.Visible ~= visible then entry.Cell.Visible = visible end
                if visible then
                    if entry.Text.Text ~= text then entry.Text.Text = text end
                    if entry.Icon.ImageColor3 ~= T.Accent then entry.Icon.ImageColor3 = T.Accent end
                end
                if entry.Divider and entry.Divider.Visible ~= (visible and seenVisible) then entry.Divider.Visible = visible and seenVisible end
                if visible then seenVisible = true end
            end
        end
        if afterLogoDivider.Visible ~= seenVisible then afterLogoDivider.Visible = seenVisible end
    end)

    watermark.Menu = attachHudMenu(self, frame, options)
    self.WatermarkInstance = watermark
    if self.HUDElements then self.HUDElements["Watermark"] = watermark end
    if self._selectedElements and self._selectedElements["Watermark"] ~= nil then
        frame.Visible = self._selectedElements["Watermark"] == true
    end
    return watermark
end

function Library:KeyStrokes(options)
    options = options or {}; options.Element = "KeyStrokes"
    local KEY, GAP = 38, 4
    local IDLE, IDLE_T = Color3.fromRGB(16, 17, 21), .25
    local TEXT_COLOR = Color3.fromRGB(226, 228, 233)
    local ks = {Mouse = options.Mouse ~= false, Space = options.Space == true, CPS = options.CPS == true, Keys = {}}
    local frame = create("Frame", {Name = "KeyStrokes", BackgroundTransparency = 1, BorderSizePixel = 0, Position = options.Position or UDim2.fromOffset(20, 330),
        Size = UDim2.fromOffset(KEY * 3 + GAP * 2, 0), AutomaticSize = Enum.AutomaticSize.Y, Active = true, Visible = false, ZIndex = 200})
    frame.Parent = self.Gui
    local layout = create("UIListLayout", {Padding = UDim.new(0, GAP), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
    layout.Parent = frame
    local clicks = {LMB = {}, RMB = {}}
    local function row(order, height)
        local r = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height or KEY), LayoutOrder = order, ZIndex = 200})
        r.Parent = frame
        local l = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, GAP), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
        l.Parent = r
        return r
    end
    local function key(parent, name, text, width, order)
        local box = create("Frame", {Name = name, BackgroundColor3 = IDLE, BackgroundTransparency = IDLE_T, BorderSizePixel = 0, Size = UDim2.new(0, width or KEY, 1, 0), LayoutOrder = order, ZIndex = 201})
        box.Parent = parent; addRound(box, 7)
        box:SetAttribute("RW_NoAccent", true)
        local t = label(box, text, 14, Enum.Font.GothamBold, TEXT_COLOR, Enum.TextXAlignment.Center)
        t.Size = UDim2.fromScale(1, 1); t.ZIndex = 202
        local sub = label(box, "", 10, Enum.Font.GothamMedium, Color3.fromRGB(150, 152, 158), Enum.TextXAlignment.Center)
        sub.AnchorPoint = Vector2.new(.5, 1); sub.Position = UDim2.new(.5, 0, 1, -3); sub.Size = UDim2.new(1, 0, 0, 11); sub.ZIndex = 202; sub.Visible = false
        ks.Keys[name] = {Box = box, Text = t, Sub = sub, Down = false}
        return box
    end
    local r1 = row(1); key(r1, "W", "W", nil, 1)
    local r2 = row(2); key(r2, "A", "A", nil, 1); key(r2, "S", "S", nil, 2); key(r2, "D", "D", nil, 3)
    local wide = math.floor((KEY * 3 + GAP * 2 - GAP) / 2)
    local r3 = row(3); key(r3, "LMB", "LMB", wide, 1); key(r3, "RMB", "RMB", wide, 2)
    local r4 = row(4, 22); key(r4, "Space", "", KEY * 3 + GAP * 2, 1)
    local bar = create("Frame", {BackgroundColor3 = TEXT_COLOR, BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.new(.4, 0, 0, 2), ZIndex = 202})
    bar.Parent = ks.Keys.Space.Box
    local function layoutRows()
        r3.Visible = ks.Mouse
        r4.Visible = ks.Space
        for _, name in ipairs({"LMB", "RMB"}) do
            local k = ks.Keys[name]
            k.Sub.Visible = ks.CPS
            k.Text.Position = ks.CPS and UDim2.fromOffset(0, -5) or UDim2.new()
        end
    end
    layoutRows()
    local function light(name, down)
        local k = ks.Keys[name]
        if not k or k.Down == down then return end
        k.Down = down
        tween(k.Box, down and .05 or .18, {BackgroundColor3 = down and T.Accent or IDLE, BackgroundTransparency = down and .1 or IDLE_T})
        tween(k.Text, down and .05 or .18, {TextColor3 = down and Color3.fromRGB(16, 17, 21) or TEXT_COLOR})
        if name == "Space" then tween(bar, down and .05 or .18, {BackgroundColor3 = down and Color3.fromRGB(16, 17, 21) or TEXT_COLOR}) end
    end
    local KEYMAP = {[Enum.KeyCode.W] = "W", [Enum.KeyCode.A] = "A", [Enum.KeyCode.S] = "S", [Enum.KeyCode.D] = "D", [Enum.KeyCode.Space] = "Space"}
    local function nameOf(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then return "LMB" end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then return "RMB" end
        return KEYMAP[input.KeyCode]
    end
    connect(UserInputService.InputBegan, function(input)
        local name = nameOf(input)
        if not name then return end
        if UserInputService:GetFocusedTextBox() and name ~= "LMB" and name ~= "RMB" then return end
        light(name, true)
        if clicks[name] then table.insert(clicks[name], os.clock()) end
    end)
    connect(UserInputService.InputEnded, function(input)
        local name = nameOf(input)
        if name then light(name, false) end
    end)

    connect(RunService.RenderStepped, function()
        if not frame.Visible then return end
        local now = os.clock()
        for name, list in pairs(clicks) do
            while list[1] and now - list[1] > 1 do table.remove(list, 1) end
            local k = ks.Keys[name]
            if ks.CPS then k.Sub.Text = #list .. " CPS" end
            if k.Down and k.Box.BackgroundColor3 ~= T.Accent then k.Box.BackgroundColor3 = T.Accent end
        end
        for _, name in ipairs({"W", "A", "S", "D", "Space"}) do
            local k = ks.Keys[name]
            if k.Down and k.Box.BackgroundColor3 ~= T.Accent then k.Box.BackgroundColor3 = T.Accent end
        end
    end)
    dragify(frame, frame)
    local library = self
    attachHudMenu(self, frame, {Element = "KeyStrokes", MenuExtra = function(menu)
        menu.Divider()
        menu.Section("Show")
        menu.CheckRow("Mouse Buttons", ks.Mouse, function(v) ks.Mouse = v; layoutRows() end)
        menu.CheckRow("Space Bar", ks.Space, function(v) ks.Space = v; layoutRows() end)
        menu.CheckRow("Clicks Per Second", ks.CPS, function(v) ks.CPS = v; layoutRows() end)
    end})
    ks.Frame = frame
    function ks:SetVisible(value) frame.Visible = value == true end
    function ks:SetOption(name, value) ks[name] = value == true; layoutRows() end
    if self.HUDElements then self.HUDElements["KeyStrokes"] = ks end
    self.KeyStrokesInstance = ks
    if self._selectedElements and self._selectedElements["KeyStrokes"] ~= nil then frame.Visible = self._selectedElements["KeyStrokes"] == true end
    return ks
end

function Library:KeybindHUD(options)

    options = options or {}; options.Element = options.Element or "Keybinds"; local hud = {Rows = {}}
    local WIDTH, TITLE_H, ROW_H = options.Width or 172, 28, 20
    local TEXT_COLOR, DIM_COLOR = Color3.fromRGB(226, 228, 233), Color3.fromRGB(140, 142, 148)
    local CHIP, CHIP_ACTIVE = Color3.fromRGB(34, 36, 41), Color3.fromRGB(56, 58, 66)
    local order = 0

    local frame = create("Frame", {Name = "KeybindHUD", BackgroundColor3 = Color3.fromRGB(16, 17, 21), BackgroundTransparency = .12, BorderSizePixel = 0, Position = options.Position or UDim2.fromOffset(20, 165), Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 200})
    frame.Parent = self.Gui; addRound(frame, 8)
    local frameLayout = create("UIListLayout", {HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
    frameLayout.Parent = frame
    hudBackdrop(self, frame, 8)

    local header = create("Frame", {Name = "Title", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, TITLE_H), LayoutOrder = 0, Active = true})
    header.Parent = frame
    local headerIcon = icon(header, "keyboard", 13, T.Accent); headerIcon.Position = UDim2.fromOffset(11, (TITLE_H - 13) / 2)
    local title = label(header, options.Title or "Keybinds", 13, Enum.Font.GothamBold, T.Text)
    title.Position = UDim2.fromOffset(31, 0); title.Size = UDim2.new(1, -42, 1, 0)

    local divider = create("Frame", {Name = "Divider", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .9, BorderSizePixel = 0, Size = UDim2.new(1, -20, 0, 1), LayoutOrder = 1, Visible = false})
    divider.Parent = frame
    local rows = create("Frame", {Name = "Rows", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false})
    rows.Parent = frame; padding(rows, 11, 9, 5, 7)
    local rowsLayout = create("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
    rowsLayout.Parent = rows

    local function refresh()
        local any = next(hud.Rows) ~= nil
        rows.Visible = any; divider.Visible = any
    end
    local function paint(entry, time)
        local active = entry.Active
        tween(entry.NameLabel, time, {TextColor3 = active and TEXT_COLOR or DIM_COLOR})
        tween(entry.KeyLabel, time, {TextColor3 = active and T.Accent or DIM_COLOR})
        tween(entry.Badge, time, {BackgroundColor3 = active and CHIP_ACTIVE or CHIP})
    end

    function hud:Add(name, key)
        if self.Rows[name] then self:Remove(name) end
        order += 1
        local row = create("Frame", {Name = "Bind", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = order})
        row.Parent = rows
        local nameLabel = label(row, name, 12, Enum.Font.GothamMedium, DIM_COLOR)
        nameLabel.Position = UDim2.fromOffset(0, 0); nameLabel.Size = UDim2.new(1, -56, 1, 0); nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        local badge = create("Frame", {BackgroundColor3 = CHIP, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X})
        badge.Parent = row; addRound(badge, 4); padding(badge, 6, 6, 0, 0)
        local keyLabel = label(badge, tostring(key), 11, Enum.Font.GothamBold, DIM_COLOR, Enum.TextXAlignment.Center)
        keyLabel.Position = UDim2.fromOffset(0, 0); keyLabel.Size = UDim2.fromOffset(0, 16); keyLabel.AutomaticSize = Enum.AutomaticSize.X
        markAccent(keyLabel, "TextColor3")
        self.Rows[name] = {Frame = row, NameLabel = nameLabel, KeyLabel = keyLabel, Badge = badge, Name = name, Key = key, Active = false}
        refresh()
        return row
    end
    function hud:Remove(name)
        if self.Rows[name] then self.Rows[name].Frame:Destroy(); self.Rows[name] = nil end
        refresh()
    end
    function hud:SetKey(name, key)
        local entry = self.Rows[name]; if entry then entry.Key = key; entry.KeyLabel.Text = tostring(key) end
    end
    function hud:SetActive(name, active)
        local entry = self.Rows[name]; if not entry then return end
        entry.Active = active == true
        paint(entry, .15)
    end
    function hud:SetStyle(style) title.Text = options.Title or "Keybinds" end

    local library = self
    if library.HideEmptyKeybinds == nil then library.HideEmptyKeybinds = true end
    task.spawn(function()
        while frame.Parent do
            local selected = not (library._selectedElements and library._selectedElements["Keybinds"] == false)
            local want = selected and (next(hud.Rows) ~= nil or not library.HideEmptyKeybinds or library.Visible == true)
            if frame.Visible ~= want then frame.Visible = want end
            task.wait(.2)
        end
    end)

    hud.Frame = frame; dragify(header, frame); options.KeybindControl = function(style) hud:SetStyle(style) end; attachHudMenu(self, frame, options)
    self.KeybindHUDInstance = hud
    if self.HUDElements then self.HUDElements["Keybinds"] = hud end
    if self._selectedElements and self._selectedElements["Keybinds"] ~= nil then
        frame.Visible = self._selectedElements["Keybinds"] == true
    end
    return hud
end

function Library:AltKeybinds(options)

    options=options or {}; options.Element="Keybinds"
    return self:KeybindHUD(options)
end

function Library:Indicator(options)
    options=options or {}; options.Element="Indicators"; local color=options.Color or Color3.fromRGB(226,77,77)

    if not self.IndicatorGroup then
        local group=create("Frame",{Name="IndicatorGroup",BackgroundTransparency=1,BorderSizePixel=0,Position=options.GroupPosition or UDim2.fromOffset(20,350),Size=UDim2.fromOffset(0,0),AutomaticSize=Enum.AutomaticSize.XY,Active=true,ZIndex=200})
        group.Parent=self.Gui
        local groupLayout=create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
        groupLayout.Parent=group
        dragify(group,group)
        self.IndicatorGroup=group
        self._indicatorCount=0
        attachHudMenu(self,group,{Element="Indicators",Position=options.GroupPosition})
    end
    local group=self.IndicatorGroup
    self._indicatorCount=(self._indicatorCount or 0)+1

    local entry=create("Frame",{Name="IndicatorEntry",BackgroundColor3=Color3.fromRGB(16,17,21),BackgroundTransparency=.12,BorderSizePixel=0,Size=UDim2.fromOffset(0,24),AutomaticSize=Enum.AutomaticSize.X,LayoutOrder=self._indicatorCount,Visible=options.Persistent~=false,ZIndex=201})
    entry.Parent=group; addRound(entry,7)
    padding(entry,8,11,0,0)
    local rowLayout=create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder})
    rowLayout.Parent=entry

    local bar=create("Frame",{BackgroundColor3=color,BorderSizePixel=0,Size=UDim2.fromOffset(2,12),LayoutOrder=0,ZIndex=202}); bar.Parent=entry; addRound(bar,1)
    local image=icon(entry,options.Icon or "swords",13,color); image.LayoutOrder=1; image.ZIndex=202
    local text=label(entry,options.Text or "INDICATOR",options.Size or 12,Enum.Font.GothamBold,Color3.fromRGB(226,228,233)); text.AutomaticSize=Enum.AutomaticSize.X; text.Size=UDim2.fromOffset(0,24); text.LayoutOrder=2; text.ZIndex=202
    hudBackdrop(self,entry,7,group.ZIndex)

    local control={Instance=entry,TextLabel=text}
    function control:Set(value,newColor)
        text.Text=tostring(value)
        if newColor then color=newColor; image.ImageColor3=color; bar.BackgroundColor3=color end
    end
    function control:SetVisible(value) entry.Visible=value==true end
    function control:SetActive(value) entry.Visible=value==true end

    self.IndicatorInstance = control
    if self.HUDElements then self.HUDElements["Indicators"] = group end
    if self._selectedElements and self._selectedElements["Indicators"] ~= nil then
        group.Visible = self._selectedElements["Indicators"] == true
    end
    return control
end

function Library:Crosshair(options)
    options = options or {}; options.Element=options.Element or "Crosshair"; local holder = create("Frame", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5,.5), Position = UDim2.fromScale(.5,.5), Size = UDim2.fromOffset(80,80), ZIndex=1})
    holder.Parent = self.Gui
    local radius, thick, color, opacity = options.Radius or options.Size or 10, options.Thickness or 2, options.Color or T.Text, options.Opacity or 0
    if string.lower(options.Style or "cross")=="circle" then
        local ring=create("Frame",{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(radius*2,radius*2)}); ring.Parent=holder; addRound(ring,radius); stroke(ring,color,thick,opacity)
    else
        local gap=options.Gap or 4
        for _, data in ipairs({
            {UDim2.new(.5,-gap-radius,.5,-thick/2), UDim2.fromOffset(radius,thick)}, {UDim2.new(.5,gap,.5,-thick/2), UDim2.fromOffset(radius,thick)},
            {UDim2.new(.5,-thick/2,.5,-gap-radius), UDim2.fromOffset(thick,radius)}, {UDim2.new(.5,-thick/2,.5,gap), UDim2.fromOffset(thick,radius)},
        }) do local line=create("Frame",{BackgroundColor3=color,BackgroundTransparency=opacity,BorderSizePixel=0,Position=data[1],Size=data[2]}); line.Parent=holder; addRound(line,thick) end
        if options.Dot then local dot=create("Frame",{BackgroundColor3=color,BackgroundTransparency=opacity,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(thick+1,thick+1)}); dot.Parent=holder; addRound(dot,thick) end
    end
    self.CrosshairElement=holder
    attachHudMenu(self,holder,options); return holder
end

function Library:SpeedGraph(options)
    options = options or {}
    local size = options.Size or Vector2.new(360, 150)
    local samplesMax = options.Samples or 90
    local rate = options.Rate or 30
    local minTop = options.Min or 20
    local unit = options.Unit or "u/sec"
    local color = options.Color or Color3.fromRGB(255, 255, 255)
    local graph = {Samples = {}, Getter = options.Getter}
    if graph.Getter == nil and options.Getter ~= false then
        graph.Getter = function()
            local character = LocalPlayer and LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return 0 end
            local v = root.AssemblyLinearVelocity
            return Vector3.new(v.X, 0, v.Z).Magnitude
        end
    end

    local frame = create("Frame", {
        Name = "SpeedGraph", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0,
        BorderSizePixel = 0, Position = options.Position or UDim2.new(0, 20, 1, -(size.Y + 20)),
        Size = UDim2.fromOffset(size.X, size.Y), Visible = options.Visible ~= false, ZIndex = 150,
    })
    frame.Parent = self.Gui
    addRound(frame, 14)

    for i, layer in ipairs({{6, 0.8}, {14, 0.9}, {24, 0.95}}) do
        local glow = create("Frame", {
            Name = "Glow" .. i, BackgroundColor3 = color, BackgroundTransparency = layer[2], BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, layer[1], 1, layer[1]), ZIndex = 149,
        })
        glow.Parent = frame
        addRound(glow, 14 + layer[1] / 2)
    end

    local plot = create("Frame", {Name = "Plot", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -34), ZIndex = 151, ClipsDescendants = true})
    plot.Parent = frame
    local caption = label(frame, "0 " .. unit, 13, Enum.Font.GothamMedium, Color3.fromRGB(150, 150, 150))
    caption.Position = UDim2.new(0, 10, 1, -22); caption.Size = UDim2.new(1, -20, 0, 18); caption.ZIndex = 151

    local segments = {}
    local function segment(i)
        local seg = segments[i]
        if not seg then
            seg = create("Frame", {BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 152})
            seg.Parent = plot
            segments[i] = seg
        end
        return seg
    end

    local top = minTop
    local function redraw()
        local samples = graph.Samples
        local w, h = plot.AbsoluteSize.X, plot.AbsoluteSize.Y
        if w <= 0 or h <= 0 then return end
        local peak = minTop
        for _, v in ipairs(samples) do if v > peak then peak = v end end
        top = top + (peak * 1.15 - top) * 0.15
        local step = w / math.max(samplesMax - 1, 1)
        local used = 0
        for i = 2, #samples do
            local x1, x2 = (i - 2) * step, (i - 1) * step
            local y1 = h - math.clamp(samples[i - 1] / top, 0, 1) * (h - 2) - 1
            local y2 = h - math.clamp(samples[i] / top, 0, 1) * (h - 2) - 1
            local dx, dy = x2 - x1, y2 - y1
            local seg = segment(i - 1)
            seg.Visible = true
            seg.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
            seg.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, 2)
            seg.Rotation = math.deg(math.atan2(dy, dx))
            used = i - 1
        end
        for i = used + 1, #segments do segments[i].Visible = false end
        caption.Text = string.format("%d %s", math.floor((samples[#samples] or 0) + 0.5), unit)
    end

    function graph:Push(value)
        table.insert(self.Samples, tonumber(value) or 0)
        while #self.Samples > samplesMax do table.remove(self.Samples, 1) end
        if frame.Visible then redraw() end
    end
    function graph:SetGetter(fn) self.Getter = fn end
    function graph:SetVisible(visible) frame.Visible = visible == true end
    function graph:SetColor(newColor)
        color = newColor
        for _, seg in ipairs(segments) do seg.BackgroundColor3 = newColor end
        for _, child in ipairs(frame:GetChildren()) do
            if string.match(child.Name, "^Glow") then child.BackgroundColor3 = newColor end
        end
    end
    local alive = true
    function graph:Destroy() alive = false; frame:Destroy() end

    local last = 0
    connect(RunService.Heartbeat, function()
        if not alive or not graph.Getter or not frame.Visible then return end
        local now = os.clock()
        if now - last < 1 / rate then return end
        last = now
        local ok, value = pcall(graph.Getter)
        graph:Push(ok and value or 0)
    end)

    graph.Frame = frame
    dragify(frame, frame)
    return graph
end

function Library:ModuleList(options)

    options = options or {}; options.Element = "ModuleList"
    local hud = {Entries = {}}
    local ROW_H, GAP, BAR_W = 25, 0, 3
    local WAVE_SPEED, WAVE_STEP = 0.18, 0.11
    local splitInfo, renderEntry

    local style = self.ModuleListStyle or {Mode = "Client", Color1 = Color3.fromRGB(165, 194, 255), Color2 = Color3.fromRGB(255, 120, 200), Speed = 1, Glow = true}
    self.ModuleListStyle = style

    local SUFFIX_STYLES = {["[Info]"] = {"[", "]"}, ["(Info)"] = {"(", ")"}, ["$ Info"] = {"$ ", ""}, ["~ Info"] = {"~ ", ""}, ["? Info"] = {"? ", ""}}
    local GLITCH_CHARS = "!@#$%&*?<>/|=+01"
    local function escapeRich(text) return (string.gsub(string.gsub(string.gsub(tostring(text), "&", "&amp;"), "<", "&lt;"), ">", "&gt;")) end
    splitInfo = function(name)
        local base, info = string.match(name, "^(.-):%s*(.+)$")
        if base and base ~= "" then return base, info end
        base, info = string.match(name, "^(.-)%s*%[(.+)%]$")
        if base and base ~= "" then return base, info end
        return name, nil
    end
    renderEntry = function(entry, glitched)
        local text = escapeRich(glitched or entry.Base)
        if entry.Info then
            local wrap = SUFFIX_STYLES[style.Suffix or "[Info]"] or SUFFIX_STYLES["[Info]"]
            text = text .. ' <font color="#8C8E96">' .. escapeRich(wrap[1] .. entry.Info .. wrap[2]) .. "</font>"
        end
        if entry.Label.Text ~= text then entry.Label.Text = text end
    end
    local function glitchText(text)
        local out = {}
        for i = 1, #text do
            local ch = string.sub(text, i, i)
            if ch ~= " " and math.random() < .4 then
                local k = math.random(1, #GLITCH_CHARS)
                ch = string.sub(GLITCH_CHARS, k, k)
            end
            out[i] = ch
        end
        return table.concat(out)
    end
    local renderedSuffix = nil
    local function modeColor(t)
        local mode = style.Mode
        if mode == "Client" then return T.Accent end
        if mode == "Fade" then
            local k = 0.5 - 0.5 * math.cos(t * math.pi * 2)
            return style.Color1:Lerp(style.Color2, k)
        end
        if mode == "Pulse" then
            local h, sat, v = style.Color1:ToHSV()
            local dark = Color3.fromHSV(h, sat, v * 0.45)
            local k = 0.5 - 0.5 * math.cos(t * math.pi * 2)
            return style.Color1:Lerp(dark, k)
        end
        return T.Accent
    end

    local frame = create("Frame", {
        Name = "ModuleListHUD",
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = options.Position or UDim2.new(1, -20, 0, 70),
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        Visible = false,
        ZIndex = 200,
    })
    frame.Parent = self.Gui
    frame:SetAttribute("RW_NoAccent", true)
    addRound(frame, 4)
    padding(frame, 12, 0, 0, 0)

    hudBackdrop(self, frame, 4)
    frame:SetAttribute("RW_NoGlow", style.BackgroundGlow ~= true)
    local library = self
    attachHudMenu(self, frame, {Element = "ModuleList", MenuExtra = function(menu)
        menu.Divider()
        menu.Section("Color Mode")
        for _, mode in ipairs({"Client", "Fade", "Pulse"}) do
            local b = menu.Row(mode, style.Mode == mode and "circle-dot" or "circle")
            connect(b.MouseButton1Click, function()
                style.Mode = mode
                if library.ModuleListModeControl then library.ModuleListModeControl:Set(mode, true) end
                menu.Close()
            end)
        end
        menu.Divider()
        menu.Section("Style")
        menu.CheckRow("Background Glow", style.BackgroundGlow == true, function(v)
            style.BackgroundGlow = v; frame:SetAttribute("RW_NoGlow", not v)
            if library.ModuleListBgGlowControl then library.ModuleListBgGlowControl:Set(v, true) end
        end)
        menu.CheckRow("Bar Glow", style.Glow ~= false, function(v)
            style.Glow = v
            if library.ModuleListGlowControl then library.ModuleListGlowControl:Set(v, true) end
        end)
        menu.CheckRow("Text Glitch", style.Glitch == true, function(v)
            style.Glitch = v
            if library.ModuleListGlitchControl then library.ModuleListGlitchControl:Set(v, true) end
        end)
    end})
    hud.SetBackgroundGlow = function(_, v) style.BackgroundGlow = v == true; frame:SetAttribute("RW_NoGlow", not style.BackgroundGlow) end

    local outer = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    outer.Parent = frame

    local column = create("Frame", {
        Name = "Column",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.XY,
        LayoutOrder = 1,
        ZIndex = 201,
    })
    column.Parent = frame
    local columnLayout = create("UIListLayout", {
        Padding = UDim.new(0, GAP),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    columnLayout.Parent = column
    padding(column, 0, 0, 4, 4)

    local bar = create("Frame", {
        Name = "AccentBar",
        BackgroundColor3 = T.Accent,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(BAR_W, 0),
        LayoutOrder = 2,
        ZIndex = 201,
    })
    bar.Parent = frame
    addRound(bar, 2)
    local barGradient = create("UIGradient", {Rotation = 90})
    barGradient.Parent = bar

    local glowGradients = {}
    for i, layer in ipairs({{4, 0.55}, {9, 0.75}, {16, 0.88}}) do
        local glow = create("Frame", {
            Name = "Glow" .. i, BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = layer[2],
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, layer[1], 1, layer[1]), ZIndex = 200,
        })
        glow.Parent = bar
        addRound(glow, math.ceil(layer[1] / 2) + 2)
        local g = create("UIGradient", {Rotation = 90})
        g.Parent = glow
        glowGradients[i] = {Frame = glow, Gradient = g}
    end

    local shine = create("Frame", {Name = "AccentShine", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 202, Visible = false})
    shine.Parent = bar
    local shineGradient = create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
    })})
    shineGradient.Parent = shine
    connect(RunService.RenderStepped, function()
        local enabled = self.AccentShineEnabled ~= false and frame.Visible and bar.Size.Y.Offset > 0
        shine.Visible = enabled
        if enabled then
            shineGradient.Offset = Vector2.new(0, -1.5 + 3 * ((os.clock() % 2.4) / 2.4))
        end
        if not frame.Visible then return end

        local now = os.clock() * WAVE_SPEED * (style.Speed or 1)
        local count = 0
        local clock = os.clock()
        local suffixChanged = renderedSuffix ~= (style.Suffix or "[Info]")
        renderedSuffix = style.Suffix or "[Info]"
        for _, entry in pairs(hud.Entries) do
            count += 1
            if style.Glitch and clock >= entry.NextGlitch then
                entry.GlitchUntil = clock + .45
                entry.NextGlitch = clock + 3 + math.random() * 6
            end
            if entry.GlitchUntil and clock < entry.GlitchUntil then
                if not entry.LastGlitch or clock - entry.LastGlitch > .05 then
                    entry.LastGlitch = clock
                    renderEntry(entry, glitchText(entry.Base))
                end
            elseif entry.GlitchUntil or suffixChanged then
                entry.GlitchUntil, entry.LastGlitch = nil, nil
                renderEntry(entry)
            end
            entry.Label.TextColor3 = modeColor((entry.Label.LayoutOrder - 1) * WAVE_STEP - now)
            if style.Font and entry.Label.FontFace ~= style.Font then entry.Label.FontFace = style.Font end
        end
        count = math.max(count, 1)
        local keys = {}
        for i = 0, 4 do
            keys[#keys + 1] = ColorSequenceKeypoint.new(i / 4, modeColor((i / 4) * count * WAVE_STEP - now))
        end
        barGradient.Color = ColorSequence.new(keys)
        for _, glow in ipairs(glowGradients) do
            glow.Frame.Visible = style.Glow ~= false
            if style.Glow ~= false then glow.Gradient.Color = barGradient.Color end
        end
    end)

    function hud:Add(name, order)
        local existing = self.Entries[name]
        if existing then
            existing.Label.LayoutOrder = order or 100
            return
        end
        local lbl = label(column, name, 18, Enum.Font.Arial, T.Text, Enum.TextXAlignment.Right)
        lbl.RichText = true
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.Size = UDim2.fromOffset(0, ROW_H)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0.75
        lbl.LayoutOrder = order or 100
        lbl.ZIndex = 202
        local base, info = splitInfo(name)
        local entry = {Label = lbl, Name = name, Base = base, Info = info, NextGlitch = os.clock() + 1 + math.random() * 5}
        self.Entries[name] = entry
        renderEntry(entry)
    end

    function hud:Remove(name)
        local entry = self.Entries[name]
        if entry then
            entry.Label:Destroy()
            self.Entries[name] = nil
        end
    end

    function hud:Update(activeList)
        if type(activeList) ~= "table" then return end

        for name in pairs(self.Entries) do
            if not activeList[name] then
                self:Remove(name)
            end
        end

        local sorted, count = {}, 0
        for name, val in pairs(activeList) do
            count += 1
            if not self.Entries[name] then self:Add(name, 1000) end

            local entry = self.Entries[name]
            local width = 0
            if entry then

                local glitching = entry.GlitchUntil ~= nil
                if glitching then
                    width = entry.StableWidth or 0
                else
                    width = entry.Label.TextBounds.X
                    if width > 0 then entry.StableWidth = width end
                end
            end
            if width <= 0 then width = #name * 9 end
            table.insert(sorted, {Name = name, Length = math.floor(width + 0.5)})
        end

        table.sort(sorted, function(a, b)
            if a.Length == b.Length then
                return a.Name < b.Name
            end
            return a.Length > b.Length
        end)

        for order, item in ipairs(sorted) do
            self:Add(item.Name, order)
        end

        local barH = count * ROW_H + math.max(count - 1, 0) * GAP
        bar.Size = UDim2.fromOffset(BAR_W, barH + 8)
        bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

        local shouldShow = count > 0
        if self.Library and self.Library._selectedElements and self.Library._selectedElements["Module List"] == false then
            shouldShow = false
        end
        frame.Visible = shouldShow
    end

    function hud:SetFont(name)
        local face = nil
        if name and name ~= "Default" then
            if BUILTIN_FONTS[name] then
                face = Font.fromEnum(BUILTIN_FONTS[name])
            else
                local file = fileFont(name)
                face = file and file.regular or nil
            end
        end
        style.Font = face or Font.fromEnum(Enum.Font.GothamBold)
    end
    if not style.Font then style.Font = Font.fromEnum(Enum.Font.GothamBold) end

    hud.Frame = frame
    hud.Library = self
    dragify(frame, frame)
    self.ModuleListControl = hud
    if self.HUDElements then self.HUDElements["Module List"] = hud end
    return hud
end

local CONFIG_DIR = ROOT_DIR .. "/configs"
local function configName(name) return (tostring(name or ""):gsub("[^%w%-%_ ]", "")) end
local function colorToHex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local function hexToColor(text)
    local raw = tostring(text or ""):gsub("#", "")
    local n = #raw == 6 and tonumber(raw, 16)
    return n and Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) or nil
end

function Library:RegisterConfigValue(id, get, set)
    self.CustomConfig = self.CustomConfig or {}
    self.CustomConfig[id] = {Get = get, Set = set}
end

function Library:GetConfigData()
    local data = {Version = 2, Values = {}, Flags = {}, Custom = {}}
    for id, entry in pairs(self.CustomConfig or {}) do
        local ok, value = pcall(entry.Get)
        if ok and value ~= nil then data.Custom[id] = value end
    end
    for _, entry in ipairs(self.ConfigControls or {}) do
        local control, value = entry.Control, nil
        if entry.Kind == "Toggle" then
            value = {Value = control.Value == true, Binds = control.GetBinds and control:GetBinds() or nil}
        elseif entry.Kind == "Color" then
            value = typeof(control.Value) == "Color3" and colorToHex(control.Value) or nil
        elseif entry.Kind == "Key" then
            local key = control.Key
            value = typeof(key) == "EnumItem" and {Key = key.Name, KeyType = tostring(key.EnumType)} or nil
        else
            local v = control.Value
            if type(v) == "number" or type(v) == "string" or type(v) == "boolean" or type(v) == "table" then value = v end
        end
        if value ~= nil then data.Values[entry.Id] = value end
    end
    for flag, control in pairs(self.Flags) do
        if control and control.Value ~= nil and type(control.Value) ~= "userdata" then data.Flags[flag] = control.Value end
    end
    return data
end

function Library:ApplyConfigData(data)
    if type(data) ~= "table" then return false, "Bad config" end
    local values = data.Values
    if values == nil then values = {}; data = {Flags = data} end
    for _, entry in ipairs(self.ConfigControls or {}) do
        local value, control = values[entry.Id], entry.Control
        if value ~= nil then
            pcall(function()
                if entry.Kind == "Toggle" then
                    if type(value) == "table" then
                        if control.SetBinds and value.Binds then control:SetBinds(value.Binds) end
                        control:Set(value.Value == true)
                    else
                        control:Set(value == true)
                    end
                elseif entry.Kind == "Color" then
                    local color = hexToColor(value)
                    if color then control:Set(color) end
                elseif entry.Kind == "Key" then
                    if type(value) == "table" and control.SetKey then
                        local enumType = value.KeyType == "UserInputType" and Enum.UserInputType or Enum.KeyCode
                        local item = enumType[value.Key]
                        if item then control:SetKey(item) end
                    end
                elseif control.Set then
                    control:Set(value)
                end
            end)
        end
    end
    for flag, value in pairs(data.Flags or {}) do
        local control = self.Flags[flag]
        if control and control.Set then pcall(control.Set, control, value) end
    end
    for id, value in pairs(data.Custom or {}) do
        local entry = self.CustomConfig and self.CustomConfig[id]
        if entry then pcall(entry.Set, value) end
    end
    return true
end

function Library:SaveConfig(name)
    name = configName(name)
    if name == "" or not writefile or not HttpService then return false, "Invalid name or filesystem unavailable" end
    if makefolder then pcall(makefolder, ROOT_DIR); pcall(makefolder, CONFIG_DIR) end
    local ok, result = pcall(function() writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(self:GetConfigData())) end)
    return ok, result
end

function Library:LoadConfig(name)
    name = configName(name)
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    if name == "" or not readfile or not isfile or not isfile(path) then return false, "Config not found" end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok then return false, data end
    return self:ApplyConfigData(data)
end

function Library:DeleteConfig(name)
    name = configName(name)
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    if name == "" or not delfile or not isfile or not isfile(path) then return false, "Config not found" end
    return pcall(delfile, path)
end

function Library:ListConfigs()
    local list = {}
    if not (listfiles and isfolder and isfolder(CONFIG_DIR)) then return list end
    for _, path in ipairs(listfiles(CONFIG_DIR)) do
        local file = tostring(path):match("[^/\\]+$") or ""
        local base = file:match("^(.+)%.json$")
        if base then table.insert(list, {Name = base}) end
    end
    table.sort(list, function(a, b) return string.lower(a.Name) < string.lower(b.Name) end)
    return list
end

function Library:_buildSettingsSection()
    if self.SettingsPanel then self.SettingsPanel:Destroy(); self.SettingsPanel=nil end
    local configTab=self:Tab({Name="Configs",Icon="folder",Pinned=true})
    local tab=self:Tab({Name="Settings",Icon="settings",Hidden=true}); self.SettingsTab=tab

    configTab.Button.Parent=self.Sidebar; configTab.Button.Position=UDim2.new(0,18,1,-164); configTab.Button.Size=UDim2.new(1,-36,0,46); configTab.Button.BackgroundColor3=T.Surface3; configTab.Button.Visible=true; self.ConfigButton=configTab.Button

    local configs=create("Frame",{Name="Configs",BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,0,1,-6)}); configs.Parent=configTab.Page
    local createBar=create("Frame",{BackgroundColor3=Color3.fromRGB(34,35,39),BorderSizePixel=0,Size=UDim2.new(1,0,0,54)}); createBar.Parent=configs; addRound(createBar,18); gradient(createBar,Color3.fromRGB(48,49,54),Color3.fromRGB(27,28,32),0)
    local configBox=create("TextBox",{Text="",PlaceholderText="config name...",PlaceholderColor3=Color3.fromRGB(155,157,162),TextColor3=T.Text,TextSize=17,Font=Enum.Font.GothamBold,ClearTextOnFocus=false,BackgroundColor3=Color3.fromRGB(36,37,41),BorderSizePixel=0,Position=UDim2.fromOffset(14,11),Size=UDim2.new(1,-260,0,32)}); configBox.Parent=createBar; addRound(configBox,8); stroke(configBox,Color3.fromRGB(119,121,126),2,.18); padding(configBox,10,10,0,0)

    local BUTTON_BASE = Color3.fromRGB(30, 31, 36)
    local BUTTON_ICONS = {Load = "download", Save = "save", Delete = "trash-2", Refresh = "refresh-cw"}
    local function configButton(parent,text,x,y,width,color,callback)
        local b=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=BUTTON_BASE,BorderSizePixel=0,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,x,0,y),Size=UDim2.fromOffset(width,32)}); b.Parent=parent; addRound(b,16)
        stroke(b,color,1,.45)
        local content=create("Frame",{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(0,32),AutomaticSize=Enum.AutomaticSize.X}); content.Parent=b
        create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder}).Parent=content
        local image=icon(content,BUTTON_ICONS[text] or "circle",14,color); image.LayoutOrder=1
        local caption=label(content,text,14,Enum.Font.GothamBold,color); caption.AutomaticSize=Enum.AutomaticSize.X; caption.Size=UDim2.fromOffset(0,32); caption.LayoutOrder=2
        connect(b.MouseEnter,function() tween(b,.12,{BackgroundColor3=BUTTON_BASE:Lerp(color,.22)}) end)
        connect(b.MouseLeave,function() tween(b,.12,{BackgroundColor3=BUTTON_BASE}) end)
        connect(b.MouseButton1Click,callback); return b
    end
    local listFrame=create("ScrollingFrame",{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(0,64),Size=UDim2.new(1,0,1,-64),CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=T.Muted})
    listFrame.Parent=configs
    create("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder}).Parent=listFrame
    local refreshConfigList
    local function notifyResult(ok,err,doneText)
        self:Notify({Type=ok and "success" or "error",Title=ok and "Successful" or "Config error",Message=ok and doneText or tostring(err)})
    end
    refreshConfigList=function()
        for _,child in ipairs(listFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
        local list=self:ListConfigs()
        if #list==0 then
            local empty=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,40)}); empty.Parent=listFrame
            local t=label(empty,"No configs yet - type a name above and press Save.",14,Enum.Font.GothamMedium,T.Muted); t.Position=UDim2.fromOffset(14,0); t.Size=UDim2.new(1,-28,1,0)
            return
        end
        for i,info in ipairs(list) do
            local item=create("Frame",{BackgroundColor3=Color3.fromRGB(26,27,31),BorderSizePixel=0,Size=UDim2.new(1,-6,0,54),LayoutOrder=i}); item.Parent=listFrame; addRound(item,14); stroke(item,Color3.fromRGB(70,72,78),1,.5)
            local fileIcon=icon(item,"file-text",18,T.Muted); fileIcon.AnchorPoint=Vector2.new(0,.5); fileIcon.Position=UDim2.new(0,16,.5,0)
            local nameLabel=label(item,info.Name,17,Enum.Font.GothamBold,T.Text); nameLabel.Position=UDim2.fromOffset(44,0); nameLabel.Size=UDim2.new(1,-400,1,0); nameLabel.TextTruncate=Enum.TextTruncate.AtEnd
            configButton(item,"Load",-234,11,104,Color3.fromRGB(110,170,255),function() local ok,err=self:LoadConfig(info.Name); notifyResult(ok,err,"Config '"..info.Name.."' loaded."); configBox.Text=info.Name end)
            configButton(item,"Save",-124,11,104,Color3.fromRGB(165,145,255),function() local ok,err=self:SaveConfig(info.Name); notifyResult(ok,err,"Config '"..info.Name.."' overwritten.") end)
            configButton(item,"Delete",-14,11,104,Color3.fromRGB(240,105,125),function() local ok,err=self:DeleteConfig(info.Name); notifyResult(ok,err,"Config deleted."); refreshConfigList() end)
        end
    end
    configButton(createBar,"Save",-124,11,104,Color3.fromRGB(165,145,255),function()
        local ok,err=self:SaveConfig(configBox.Text); notifyResult(ok,err,"Config saved."); refreshConfigList()
    end)
    configButton(createBar,"Refresh",-14,11,104,Color3.fromRGB(185,187,195),function() refreshConfigList() end)
    refreshConfigList()
    if configTab.Button then connect(configTab.Button.MouseButton1Click,function() refreshConfigList() end) end

    local interface=self:Card(tab,{Title="Interface",Side="left"})
    local selectedElements={Watermark=true,Keybinds=true,Indicators=true,["Module List"]=true,["Toggle UI Button"]=false,KeyStrokes=false}
    self._selectedElements=selectedElements

    if not self.WatermarkInstance then self.WatermarkInstance = self:Watermark() end
    if not self.KeybindHUDInstance then self.KeybindHUDInstance = self:KeybindHUD() end
    if not self.KeyStrokesInstance then self:KeyStrokes() end

    if not self.ModuleListControl then self.ModuleListControl = self:ModuleList() end

    local function applyHudVisibility(values)
        if self.WatermarkInstance and self.WatermarkInstance.Frame then
            self.WatermarkInstance.Frame.Visible = values["Watermark"] == true
        end
        if self.KeybindHUDInstance and self.KeybindHUDInstance.Frame then
            self.KeybindHUDInstance.Frame.Visible = values["Keybinds"] == true
        end
        if self.IndicatorGroup then
            self.IndicatorGroup.Visible = values["Indicators"] == true
        end
        if self.ModuleListControl and self.ModuleListControl.Frame then
            self.ModuleListControl.Frame.Visible = values["Module List"] == true
        end
        if self.ToggleButton then
            self.ToggleButton.Visible = values["Toggle UI Button"] == true
        end
        if self.KeyStrokesInstance then
            self.KeyStrokesInstance:SetVisible(values["KeyStrokes"] == true)
        end
    end

    self:Dropdown(interface,{
        Name="Elements",
        Values={"Watermark","Keybinds","Indicators","Module List","Toggle UI Button","KeyStrokes"},
        Default=selectedElements,
        Multi=true,
        Callback=function(value)
            selectedElements=value
            self._selectedElements=value
            applyHudVisibility(value)
        end
    })
    applyHudVisibility(selectedElements)
    self:Toggle(interface,{Name="Hide Empty Keybinds",Default=self.HideEmptyKeybinds~=false,Bindable=false,Callback=function(value) self.HideEmptyKeybinds=value end})
    self:Dropdown(interface,{Name="Toggle UI Button Style",Values={"Var. 1 (Square)","Var. 2 (wide, full name)"},Default="Var. 1 (Square)",Callback=function(value) self:_createToggle(string.find(value,"Var. 2",1,true) and 2 or 1) end})

    local moduleCard=self:Card(tab,{Title="Module List",Side="right"})
    local mlStyle=self.ModuleListStyle or {Mode="Client",Color1=Color3.fromRGB(165,194,255),Color2=Color3.fromRGB(255,120,200),Speed=1,Glow=true}
    self.ModuleListStyle=mlStyle

    local mlColor1, mlColor2, mlSpeed
    local function mlShow()
        if not (mlColor1 and mlColor2 and mlSpeed) then return end
        mlColor1.Row.Visible = mlStyle.Mode ~= "Client"
        mlColor2.Row.Visible = mlStyle.Mode == "Fade"
        mlSpeed.Row.Visible = mlStyle.Mode ~= "Client"
    end
    self.ModuleListModeControl=self:Dropdown(moduleCard,{Name="Color Mode",Values={"Client","Fade","Pulse"},Default=mlStyle.Mode,Callback=function(value) mlStyle.Mode=value; mlShow() end})
    mlColor1=self:ColorPicker(moduleCard,{Name="Color 1",Default=mlStyle.Color1,Callback=function(value) mlStyle.Color1=value end})
    mlColor2=self:ColorPicker(moduleCard,{Name="Color 2",Default=mlStyle.Color2,Callback=function(value) mlStyle.Color2=value end})
    mlSpeed=self:Slider(moduleCard,{Name="Color Speed",Min=0.2,Max=4,Default=1,Step=0.1,Callback=function(value) mlStyle.Speed=value end})
    mlShow()
    self.ModuleListGlowControl=self:Toggle(moduleCard,{Name="Bar Glow",Default=mlStyle.Glow~=false,Bindable=false,Callback=function(value) mlStyle.Glow=value end})
    self.ModuleListBgGlowControl=self:Toggle(moduleCard,{Name="Background Glow",Default=mlStyle.BackgroundGlow==true,Bindable=false,Callback=function(value)
        if self.ModuleListControl and self.ModuleListControl.SetBackgroundGlow then self.ModuleListControl:SetBackgroundGlow(value) else mlStyle.BackgroundGlow=value end
    end})
    self:Dropdown(moduleCard,{Name="Suffix Style",Values={"[Info]","(Info)","$ Info","~ Info","? Info"},Default=mlStyle.Suffix or "[Info]",Callback=function(value) mlStyle.Suffix=value end})
    self.ModuleListGlitchControl=self:Toggle(moduleCard,{Name="Text Glitch",Default=mlStyle.Glitch==true,Bindable=false,Callback=function(value) mlStyle.Glitch=value end})
    self:Dropdown(moduleCard,{Name="Font",Values=self:ListFonts(),Default="Default",OnOpen=function(control) control:SetValues(self:ListFonts()) end,Callback=function(value)
        if self.ModuleListControl and self.ModuleListControl.SetFont then self.ModuleListControl:SetFont(value) end
    end})

    local ui=self:Card(tab,{Title="UI Settings",Side="left"})

    local ACCENT_PROPS = {GuiObject = "BackgroundColor3", TextLabel = "TextColor3", ImageLabel = "ImageColor3", UIStroke = "Color"}
    local accent = {Color1 = T.Accent, Color2 = Color3.fromRGB(150, 120, 255), Mode = "Static", Speed = 1}
    self.AccentStyle = accent
    local function secondColor()
        if accent.Mode == "Pulse" then
            local h, sat, v = accent.Color1:ToHSV()
            return Color3.fromHSV(h, sat, v * 0.45)
        end
        return accent.Color2
    end

    local function onPath(c)
        local a, b = accent.Color1, secondColor()
        local ab = Vector3.new(b.R - a.R, b.G - a.G, b.B - a.B)
        local ac = Vector3.new(c.R - a.R, c.G - a.G, c.B - a.B)
        local len = ab:Dot(ab)
        local k = len > 0 and math.clamp(ac:Dot(ab) / len, 0, 1) or 0
        return (ac - ab * k).Magnitude < 0.02
    end
    local excludedCache = {}
    local function excluded(object)
        local cached = excludedCache[object]
        if cached ~= nil then return cached end
        local current, result = object, false
        while current and current ~= self.Gui do
            if current:GetAttribute("RW_NoAccent") then result = true; break end
            current = current.Parent
        end
        excludedCache[object] = result
        return result
    end

    task.spawn(function()
        while self.Gui and self.Gui.Parent do
            task.wait(5)
            for object in pairs(accentRegistry) do
                if not object:IsDescendantOf(game) then accentRegistry[object] = nil; excludedCache[object] = nil end
            end
        end
    end)
    local lastColor = T.Accent
    local function readProp(object, prop) return object[prop] end
    local function writeProp(object, prop, value) object[prop] = value end
    local function paintAccent(color, animated)
        local previous = lastColor
        T.Accent = color; lastColor = color
        for object, props in pairs(accentRegistry) do
            if object.Parent and object:IsDescendantOf(self.Gui) and not excluded(object) then
                for prop in pairs(props) do
                    local ok, current = pcall(readProp, object, prop)
                    if ok and typeof(current) == "Color3" and current ~= color and (current == previous or (animated and onPath(current))) then
                        pcall(writeProp, object, prop, color)
                    end
                end
            end
        end
    end
    local lastPaint = 0
    connect(RunService.Heartbeat, function()
        if accent.Mode == "Static" then return end
        local now = os.clock()
        if now - lastPaint < (self.Visible and 0.05 or 0.1) then return end
        lastPaint = now
        local k = 0.5 - 0.5 * math.cos(now * 0.9 * accent.Speed)
        paintAccent(accent.Color1:Lerp(secondColor(), k), true)
    end)
    local accentColor2, accentSpeed
    local function accentShow()
        if accentColor2 then accentColor2.Row.Visible = accent.Mode == "Fade" end
        if accentSpeed then accentSpeed.Row.Visible = accent.Mode ~= "Static" end
    end
    self:Dropdown(ui,{Name="Accent Color Mode",Values={"Static","Fade","Pulse"},Default="Static",Callback=function(value)
        local wasAnimated = accent.Mode ~= "Static"
        accent.Mode = value
        if value == "Static" then paintAccent(accent.Color1, wasAnimated) end
        accentShow()
    end})
    self:ColorPicker(ui,{Name="Accent Color",Default=T.Accent,Callback=function(color)
        accent.Color1 = color
        if accent.Mode == "Static" then paintAccent(color, false) end
    end})
    accentColor2 = self:ColorPicker(ui,{Name="Accent Color 2",Default=accent.Color2,Callback=function(color) accent.Color2 = color end})
    accentSpeed = self:Slider(ui,{Name="Accent Speed",Min=0.2,Max=4,Default=1,Step=0.1,Callback=function(value) accent.Speed = value end})
    accentShow()
    self:Dropdown(ui,{Name="Notification Position",Values=Library.NotificationPositions,Default=self.NotificationPosition or "Bottom Right",Callback=function(value)
        self.NotificationPosition=value; self:_placeNotifications()
    end})

    self.MenuScaleControl = self:Slider(ui,{Name="Click GUI Scale",Min=25,Max=125,Default=100,Step=5,Suffix="%",Callback=function(value) self:SetMenuScale(value / 100) end})
    self:Dropdown(ui,{Name="Interface Scale",Values={"25%","50%","75%","100%","125%"},Default="100%",Callback=function(value)
        local n = tonumber((tostring(value):gsub("%%", "")))
        if n then self:SetInterfaceScale(n / 100) end
    end})
    local cursorState = self:SetupCursor()
    local cursorNames = self:ListCursors()
    cursorState.Style = cursorNames[1]
    self:Toggle(ui,{Name="Custom Cursor",Default=false,Bindable=false,Callback=function(v) cursorState.Enabled=v end})
    self:Dropdown(ui,{Name="Cursor Style",Values=#cursorNames>0 and cursorNames or {"(no cursors)"},Default=cursorNames[1],Search=true,
        OnOpen=function(control) local list=self:ListCursors(); if #list>0 then control:SetValues(list) end end,
        Callback=function(v) if self.CursorAssets and self.CursorAssets[v] then cursorState.Style=v end end})
    self:Slider(ui,{Name="Cursor Size",Min=16,Max=96,Default=32,Step=1,Suffix=" px",Callback=function(v) cursorState.Size=v end})
    self:Toggle(ui,{Name="Cursor In Game",Default=false,Bindable=false,Callback=function(v) cursorState.InGame=v end})
    self:Dropdown(ui,{Name="UI Font",Values=self:ListFonts(),Default="Default",OnOpen=function(control) control:SetValues(self:ListFonts()) end,Callback=function(value) self:SetFont(value) end})
    self.ToggleSoundName = "Default"
    self.AccentShineEnabled = true
    self:Toggle(ui,{Name="Accent Shine",Default=true,Callback=function(value) self.AccentShineEnabled=value end})

    local crosshair=self:Card(tab,{Title="Crosshair",Side="right"})
    local crosshairOptions={Style="Circle",Radius=10,Thickness=2,Opacity=0,Dot=false,Color=T.Text}
    local crosshairShown=true
    local function refresh()
        if self.CrosshairElement then self.CrosshairElement:Destroy(); self.CrosshairElement=nil end
        if crosshairShown then self:Crosshair(crosshairOptions) end
    end
    self:Toggle(crosshair,{Name="Show Crosshair",Default=true,Callback=function(value) crosshairShown=value; refresh() end})
    self:Dropdown(crosshair,{Name="Style",Values={"Circle","Cross"},Default="Circle",Callback=function(value) crosshairOptions.Style=value; refresh() end})
    self:Slider(crosshair,{Name="Radius",Min=3,Max=30,Default=10,Callback=function(value) crosshairOptions.Radius=value; refresh() end})
    self:Slider(crosshair,{Name="Thickness",Min=1,Max=8,Default=2,Callback=function(value) crosshairOptions.Thickness=value; refresh() end})
    self:Slider(crosshair,{Name="Opacity",Min=0,Max=100,Default=0,Suffix="%",Callback=function(value) crosshairOptions.Opacity=value/100; refresh() end})
    self:Toggle(crosshair,{Name="Dot",Default=false,Callback=function(value) crosshairOptions.Dot=value; refresh() end})
    self:ColorPicker(crosshair,{Name="Color",Default=T.Text,Callback=function(value) crosshairOptions.Color=value; refresh() end})
end

function Library:Destroy()
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
    pcall(function() RunService:UnbindFromRenderStep("RW_MenuMouse") end)
    if self.Gui then self.Gui:Destroy() end
end

function Library:ListFonts()
    ensureFolder(FONT_DIR)
    local list = {"Default"}
    for _, name in ipairs(BUILTIN_FONT_ORDER) do table.insert(list, name) end
    for _, name in ipairs(scanFolder(FONT_DIR, {ttf = true, otf = true}, fontFiles)) do
        if not BUILTIN_FONTS[name] then table.insert(list, name) end
    end
    return list
end

function Library:SetFont(name)
    if name == nil or name == "Default" then
        ActiveFont = nil
    elseif BUILTIN_FONTS[name] then
        ActiveFont = {enum = BUILTIN_FONTS[name]}
    else
        ActiveFont = fileFont(name)
    end
    for _, object in ipairs(self.Gui:GetDescendants()) do
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then

            if originalFonts[object] == nil then originalFonts[object] = object.FontFace end
            pcall(applyFont, object, originalFonts[object])
        end
    end
end

function Library:ResolveFont(name, bold)
    if name == nil or name == "Default" then return nil end
    if BUILTIN_FONTS[name] then
        local face = Font.fromEnum(BUILTIN_FONTS[name])
        return Font.new(face.Family, bold and Enum.FontWeight.Bold or face.Weight, face.Style)
    end
    local file = fileFont(name)
    return file and (bold and file.bold or file.regular) or nil
end

function Library:GetClientFont(bold)
    if not ActiveFont then return nil end
    if ActiveFont.enum then
        local face = Font.fromEnum(ActiveFont.enum)
        return Font.new(face.Family, bold and Enum.FontWeight.Bold or face.Weight, face.Style)
    end
    return bold and ActiveFont.bold or ActiveFont.regular
end

local CURSOR_HOTSPOT = {
    ChromeHearts = {33, 40}, CodeGeass = {1, 5}, FlowerBear = {11, 22}, FlowerBearSmall = {15, 24}, HelloKitty = {15, 17},
    SakuraFawn = {6, 11}, SakuraFawnSmall = {14, 19}, UnicornPusheen = {13, 18}, UnicornPusheenSmall = {18, 19}, WhiteAlicornPusheen = {15, 20},
}
function Library:ListCursors()
    self.CursorAssets = self.CursorAssets or {}
    local names = {}
    for _, dir in ipairs({ROOT_DIR .. "/assets/cursors", ROOT_DIR .. "/cursors"}) do
        pcall(function()
            if not (isfolder and isfolder(dir) and listfiles and getcustomasset) then return end
            for _, path in ipairs(listfiles(dir)) do
                local name = string.match((string.gsub(tostring(path), "\\", "/")), "([^/]+)%.png$")
                if name and not self.CursorAssets[name] then
                    local ok, asset = pcall(getcustomasset, dir .. "/" .. name .. ".png")
                    if ok and type(asset) == "string" and asset ~= "" then self.CursorAssets[name] = asset end
                end
            end
        end)
    end
    for name in pairs(self.CursorAssets) do table.insert(names, name) end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end
function Library:_cursorStep()
    local cursor = self.CursorState
    if not cursor then return end
    local art = self.CursorAssets and self.CursorAssets[cursor.Style]
    local wanted = cursor.Enabled and art ~= nil and (self.Visible or cursor.InGame)
    local image = cursor.Image
    if not wanted then
        if image.Visible then image.Visible = false end
        if cursor.Kept ~= nil then UserInputService.MouseIconEnabled = cursor.Kept; cursor.Kept = nil end
        return
    end
    if cursor.Kept == nil then cursor.Kept = UserInputService.MouseIconEnabled end
    local spot = CURSOR_HOTSPOT[cursor.Style]
    image.Image = art
    image.AnchorPoint = spot and Vector2.new(spot[1] / 64, spot[2] / 64) or Vector2.new(.5, .5)
    image.Size = UDim2.fromOffset(cursor.Size, cursor.Size)
    local p = UserInputService:GetMouseLocation()
    image.Position = UDim2.fromOffset(p.X, p.Y)
    local locked = not self.Visible and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
    image.Visible = not locked
    if UserInputService.MouseIconEnabled ~= locked then UserInputService.MouseIconEnabled = locked end
end
function Library:SetupCursor()
    if self.CursorState then return self.CursorState end
    local holder = create("ScreenGui", {Name = "RarelyWinCursor", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2147483647, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    pcall(function() holder.Parent = self.Gui.Parent end)
    local image = create("ImageLabel", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(32, 32), Visible = false, ZIndex = 10})
    image.Parent = holder
    pcall(function() image.ResampleMode = Enum.ResamplerMode.Pixelated end)
    self.CursorState = {Enabled = false, InGame = false, Size = 32, Style = nil, Image = image, Gui = holder}
    connect(RunService.RenderStepped, function() pcall(self._cursorStep, self) end)
    return self.CursorState
end

function Library:ListSounds()
    ensureFolder(SOUND_DIR)
    local list = {"Default"}
    for _, name in ipairs(scanFolder(SOUND_DIR, {mp3 = true, ogg = true, wav = true}, soundFiles)) do
        table.insert(list, name)
    end
    return list
end

function Library:PlayToggleSound(name)
    name = name or self.ToggleSoundName or "Default"
    local id = soundIdFor(name)
    if not id then
        warn("[RarelyWinUI] toggle sound '" .. tostring(name) .. "' was not found in " .. SOUND_DIR)
        return
    end
    local sound = self.ToggleSound
    if not (sound and sound.Parent) then
        sound = Instance.new("Sound")
        sound.Volume = .22
        sound.Parent = self.Gui
        self.ToggleSound = sound
    end
    sound.SoundId = id
    sound:Play()
end

function Library:Panel(tab, options)
    options = options or {}
    local frame = create("Frame", {Name = "Panel_" .. tostring(options.Subcategory), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false})
    frame.Parent = tab.Page
    table.insert(tab.Panels, {Frame = frame, Subcategory = options.Subcategory})
    tab:ApplyFilter()
    return frame
end

function Library:Preview(parent, options)
    options = options or {}
    local frame = create("Frame", {BackgroundColor3 = Color3.fromRGB(13, 12, 27), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -(options.Inset or 0))})
    frame.Parent = parent
    addRound(frame, 12)
    local viewport = create("ViewportFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -40), Ambient = Color3.fromRGB(170, 160, 220), LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(-1, -1, -1)})
    viewport.Parent = frame
    local world = Instance.new("WorldModel")
    world.Parent = viewport
    local camera = Instance.new("Camera")
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    local caption = label(frame, "", 14, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
    caption.Position = UDim2.new(0, 8, 1, -30); caption.Size = UDim2.new(1, -16, 0, 24)

    local preview = {Frame = frame}
    local model, track = nil, nil
    local angle = 0
    connect(RunService.RenderStepped, function(dt)
        if not (model and model.Parent) then return end
        angle += dt * 0.5
        local center, size = model:GetBoundingBox()
        local distance = math.max(size.Y, 3) * 1.8
        local origin = center.Position
        camera.CFrame = CFrame.lookAt(origin + Vector3.new(math.sin(angle) * distance, size.Y * 0.1, math.cos(angle) * distance), origin)
    end)

    function preview:SetCaption(text)
        caption.Text = tostring(text or "")
    end
    function preview:SetModel(source)
        if track then track:Stop(); track = nil end
        if model then model:Destroy(); model = nil end
        if not source then return end
        model = source:Clone()
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
            elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
                descendant:Destroy()
            end
        end
        model.Parent = world
        if model:IsA("Model") then model:PivotTo(CFrame.new(0, 0, 0)) end
    end
    function preview:PlayAnimation(animation)
        if track then track:Stop(); track = nil end
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        if not (humanoid and animation) then return end
        local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
        animator.Parent = humanoid
        track = animator:LoadAnimation(animation)
        track.Looped = true
        track:Play()
    end
    function preview:Stop()
        if track then track:Stop(); track = nil end
    end
    return preview
end

function Library:Gallery(parent, options)
    options = options or {}
    local scroll = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = T.Accent})
    scroll.Parent = parent
    local grid = create("UIGridLayout", {CellSize = UDim2.fromOffset(options.CellWidth or 160, options.CellHeight or 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder})
    grid.Parent = scroll
    padding(scroll, 4, 6, 4, 4)

    local gallery = {Tiles = {}, Selected = nil}
    function gallery:SetItems(items)
        for _, tile in ipairs(self.Tiles) do tile:Destroy() end
        table.clear(self.Tiles)
        self.Selected = nil
        for index, item in ipairs(items) do
            local tile = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = T.Surface2, BackgroundTransparency = .1, BorderSizePixel = 0, LayoutOrder = index})
            tile.Parent = scroll
            addRound(tile, 8)
            local name = label(tile, item.Name, 14, Enum.Font.GothamBold, T.Text)
            name.Position = UDim2.fromOffset(10, 0); name.Size = UDim2.new(1, -20, 1, 0); name.TextTruncate = Enum.TextTruncate.AtEnd
            connect(tile.MouseButton1Click, function() gallery:Select(tile, item) end)
            table.insert(self.Tiles, tile)
        end
    end
    function gallery:Select(tile, item)
        for _, other in ipairs(self.Tiles) do
            tween(other, .15, {BackgroundColor3 = other == tile and T.AccentDark or T.Surface2})
        end
        self.Selected = item
        safeCallback(options.OnSelect, item)
    end
    return gallery
end

return Library
