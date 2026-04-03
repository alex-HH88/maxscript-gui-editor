/**
 * MAXScript GUI Editor
 * Visual Rollout Designer for 3ds Max
 * Generates clean Rollout or MacroScript code
 * Version: 1.00  |  Requires: 3ds Max 2022+
 */

-- ==============================================================
-- SECTION 1: VERSION & COMPATIBILITY
-- ==============================================================

global TOOLS_VERSION = "1.09"

if (maxVersion())[1] / 1000 < 24 do
(
	messageBox "MAXScript GUI Editor requires 3ds Max 2022 or later." title:"GUI Editor"
	return undefined
)

-- ==============================================================
-- SECTION 2: STRUCTS  (global scope — required for .dat serialization)
-- ==============================================================

struct rolloutConstructor
(
	rolloutName     = "RL_Rollout",
	rolloutTitle    = "My Rollout",
	rolloutWidth    = 330,
	rolloutHeight   = 500,
	useHeight       = false,
	usePos          = false,
	pos             = [100, 100],
	bgcolor         = undefined,
	fgcolor         = undefined,
	useBitmap       = false,
	bitmap          = undefined,
	bmpstyle        = undefined,
	style           = #(#style_titlebar, #style_border, #style_sysmenu, #style_minimizebox, #style_resizing),
	lockWidth       = false,
	lockHeight      = false,
	doEscapeEnable  = false,
	modal           = false,
	controls        = #(),
	activeControl   = 0,
	eventHandlers   = #()
)

struct UIControlStruct
(
	controlType     = "",
	controlName     = "",
	label           = "",
	usePos          = false,   pos             = [0, 0],
	useWidth        = false,   width           = 100,
	useHeight       = false,   height          = 20,
	useOffset       = false,   offset          = [0, 0],
	useAlign        = false,   align           = #left,
	useAcross       = false,   across          = 1,
	usePercentageWidth = false, percentageWidth = 50,
	enabled         = undefined,
	useVisible      = false,   visible         = true,
	tooltip         = "",
	comment         = "",
	range           = undefined,
	type            = undefined,
	indeterminate   = undefined,
	controller      = undefined,
	setKeyBrackets  = undefined,
	scale           = undefined,
	useFieldWidth   = false,   fieldWidth      = 45,
	checked         = undefined,
	useTriState     = false,   triState        = 0,
	state           = undefined,
	color           = undefined,
	alpha           = undefined,
	modal           = undefined,
	title           = undefined,
	items           = undefined,
	selection       = undefined,
	readOnly        = undefined,
	labels          = undefined,
	useColumns      = false,   columns         = 2,
	offsets         = undefined,
	text            = undefined,
	labelOnTop      = undefined,
	bold            = undefined,
	border          = undefined,
	images          = undefined,
	highlightColor  = undefined,
	message         = undefined,
	filter          = undefined,
	autoDisplay     = undefined,
	map             = undefined,
	material        = undefined,
	address         = undefined,
	hoverColor      = undefined,
	visitedColor    = undefined,
	ticks           = undefined,
	orient          = undefined,
	degrees         = undefined,
	diameter        = undefined,
	startDegree     = undefined,
	startRadians    = undefined,
	dir             = undefined,
	bitmap          = undefined,
	filename        = undefined,
	opacity         = undefined,
	transparent     = undefined,
	style           = undefined,
	value           = undefined,
	style_sunkenEdge = undefined,
	interval        = undefined,
	active          = undefined,
	numCurves       = undefined,
	x_range         = undefined,
	y_range         = undefined,
	x_value         = undefined,
	zoomValues      = undefined,
	scrollValues    = undefined,
	commandMode     = undefined,
	uiFlags         = undefined,
	rcmFlags        = undefined,
	asPopup         = undefined,
	eventHandlers   = #()
)

struct eventHandlerStruct
(
	event = "pressed",
	args  = "",
	code  = "\t\t-- code here\n"
)

struct macroScriptConfigStruct
(
	scriptName   = "MyTool",
	category     = "Tools",
	internalName = "MyTool",
	toolTip      = "My Tool",
	buttonText   = "My Tool"
)

-- ==============================================================
-- SECTION 3: GLOBAL STATE
-- ==============================================================

if GUI_EditorPos      == undefined do persistent global GUI_EditorPos
if newRollout         == undefined do global newRollout         = rolloutConstructor()
if macroScriptConfig  == undefined do global macroScriptConfig  = macroScriptConfigStruct()
if _undoStack         == undefined do global _undoStack         = #()
if _undoIdx           == undefined do global _undoIdx           = 0
global _MAX_UNDO = 20
global RL_Preview    = undefined
global RL_GUIEditor  = undefined

-- Migrate struct fields if loaded from older version
(
	local fresh = rolloutConstructor()
	for p in getpropnames fresh do
		if (getproperty newRollout p) == undefined do
			try(setproperty newRollout p (getproperty fresh p)) catch()
)

-- ==============================================================
-- SECTION 4: UTILITY FUNCTIONS
-- ==============================================================

fn checkString str =
(
	local rx = dotNetObject "System.Text.RegularExpressions.Regex" "(?<!\\\\)\""
	while rx.isMatch str do str = rx.Replace str "\\\""
	str
)

fn deepCopyControl ctrl =
(
	local nc = UIControlStruct()
	for p in getpropnames ctrl do
		try(setproperty nc p (getproperty ctrl p)) catch()
	nc.eventHandlers = for eh in ctrl.eventHandlers collect
		eventHandlerStruct event:eh.event args:eh.args code:eh.code
	nc
)

fn deepCopyRollout r =
(
	local c = rolloutConstructor()
	for p in getpropnames r do
		try(setproperty c p (getproperty r p)) catch()
	c.controls = for ctrl in r.controls collect deepCopyControl ctrl
	c.eventHandlers = for eh in r.eventHandlers collect
		eventHandlerStruct event:eh.event args:eh.args code:eh.code
	c
)

fn getUniqueControlName baseName =
(
	local names = for o in newRollout.controls collect o.controlName
	if findItem names (baseName + "1") == 0 then
		baseName + "1"
	else
	(
		local nums = #()
		for n in names where matchPattern n pattern:(baseName + "*") do
		(
			local parts = filterString n "_"
			if parts.count >= 2 do
				try(append nums (parts[parts.count] as integer)) catch()
		)
		if nums.count == 0 then baseName + "1"
		else ( nums = sort nums; baseName + ((nums[nums.count]) + 1) as string )
	)
)

fn getValidEvents ctrlType =
(
	case ctrlType of
	(
		"button"         : #("pressed")
		"checkbutton"    : #("changed")
		"pickbutton"     : #("picked", "rightClick")
		"mapbutton"      : #("picked", "rightClick")
		"materialbutton" : #("picked", "rightClick")
		"checkbox"       : #("changed")
		"spinner"        : #("changed")
		"slider"         : #("changed")
		"edittext"       : #("changed", "entered")
		"dropdownlist"   : #("selected")
		"listbox"        : #("selected", "doubleClicked")
		"multilistbox"   : #("selected")
		"combobox"       : #("selected", "entered")
		"colorpicker"    : #("changed")
		"radiobuttons"   : #("changed")
		"angle"          : #("changed")
		"timer"          : #("tick")
		"hyperlink"      : #("pressed")
		"imgTag"         : #("mouseover", "mouseout", "click")
		"curveControl"   : #("ptChanged", "reset")
		default          : #()
	)
)

-- ==============================================================
-- SECTION 5: UNDO / REDO ENGINE
-- ==============================================================

fn pushUndo =
(
	if _undoIdx < _undoStack.count do
	(
		local trimmed = #()
		for i = 1 to _undoIdx do append trimmed _undoStack[i]
		_undoStack = trimmed
	)
	append _undoStack (deepCopyRollout newRollout)
	if _undoStack.count > _MAX_UNDO do deleteItem _undoStack 1
	_undoIdx = _undoStack.count
)

fn doUndo =
(
	if _undoIdx > 1 do
	(
		_undoIdx -= 1
		newRollout = deepCopyRollout _undoStack[_undoIdx]
	)
)

fn doRedo =
(
	if _undoIdx < _undoStack.count do
	(
		_undoIdx += 1
		newRollout = deepCopyRollout _undoStack[_undoIdx]
	)
)

-- ==============================================================
-- SECTION 6: CODE GENERATOR
-- ==============================================================

fn buildCommonParamStr ui =
(
	local s = ""
	if ui.useAcross  do append s (" across:" + ui.across as string)
	if ui.usePos     do append s (" pos:" + ui.pos as string)
	if ui.useOffset  do append s (" offset:" + ui.offset as string)
	if ui.useAlign   do append s (" align:#" + ui.align as string)
	if ui.usePercentageWidth then
	(
		local pw = ((newRollout.rolloutWidth as float) / 100.0 * ui.percentageWidth) as integer
		append s (" width:" + pw as string)
	)
	else if ui.useWidth do append s (" width:" + ui.width as string)
	if ui.useHeight  do append s (" height:" + ui.height as string)
	if ui.enabled != undefined do append s (" enabled:" + ui.enabled as string)
	if ui.useVisible do append s (" visible:" + ui.visible as string)
	s
)

fn buildControlParamStr ui =
(
	local s = ""
	case ui.controlType of
	(
		"label": (
			if ui.style_sunkenEdge != undefined do
				append s (" style_sunkenedge:" + ui.style_sunkenEdge as string)
		)
		"button": (
			if ui.border != undefined do append s (" border:" + ui.border as string)
		)
		"checkbutton": (
			if ui.highlightColor != undefined do append s (" highlightColor:" + ui.highlightColor as string)
			if ui.checked != undefined do append s (" checked:" + ui.checked as string)
		)
		"pickbutton": (
			if ui.message != undefined do append s (" message:\"" + ui.message + "\"")
			if ui.filter  != undefined do append s (" filter:" + ui.filter as string)
			if ui.autoDisplay != undefined do append s (" autoDisplay:" + ui.autoDisplay as string)
		)
		"mapbutton": (
			if ui.map    != undefined do append s (" map:" + ui.map as string)
			if ui.border != undefined do append s (" border:" + ui.border as string)
		)
		"materialbutton": (
			if ui.material != undefined do append s (" material:" + ui.material as string)
			if ui.border   != undefined do append s (" border:" + ui.border as string)
		)
		"spinner": (
			local t = if ui.type != undefined then (ui.type as string) else "float"
			append s (" type:#" + t)
			if ui.range != undefined do append s (" range:" + ui.range as string)
			if ui.useFieldWidth do append s (" fieldWidth:" + ui.fieldWidth as string)
			if ui.indeterminate  != undefined do append s (" indeterminate:" + ui.indeterminate as string)
			if ui.controller     != undefined do append s (" controller:" + ui.controller as string)
			if ui.setKeyBrackets != undefined do append s (" setKeyBrackets:" + ui.setKeyBrackets as string)
			if ui.scale != undefined do append s (" scale:" + ui.scale as string)
		)
		"checkbox": (
			if ui.checked != undefined do append s (" checked:" + ui.checked as string)
			if ui.useTriState and ui.triState != undefined do
				append s (" triState:" + ui.triState as string)
		)
		"colorpicker": (
			if ui.color != undefined do append s (" color:" + ui.color as string)
			if ui.useFieldWidth do append s (" fieldWidth:" + ui.fieldWidth as string)
			if ui.modal  != undefined do append s (" modal:" + ui.modal as string)
			if ui.title  != undefined do append s (" title:\"" + ui.title + "\"")
			if ui.alpha  != undefined do append s (" alpha:" + ui.alpha as string)
		)
		"edittext": (
			if ui.labelOnTop != undefined do append s (" labelOnTop:" + ui.labelOnTop as string)
			if ui.text != undefined do append s (" text:\"" + ui.text + "\"")
			if ui.bold != undefined do append s (" bold:" + ui.bold as string)
			if ui.readOnly != undefined do append s (" readOnly:" + ui.readOnly as string)
			if ui.useFieldWidth do append s (" fieldWidth:" + ui.fieldWidth as string)
		)
		"listbox": (
			if ui.items != undefined do append s (" items:" + ui.items as string)
			if ui.selection != undefined do append s (" selection:" + ui.selection as string)
			if ui.readOnly  != undefined do append s (" readOnly:" + ui.readOnly as string)
		)
		"multilistbox": (
			-- BUG FIX vs DW: use .items not .labels
			if ui.items != undefined do append s (" items:" + ui.items as string)
			if ui.selection != undefined do append s (" selection:" + ui.selection as string)
		)
		"combobox": (
			if ui.items != undefined do append s (" items:" + ui.items as string)
			if ui.selection != undefined do append s (" selection:" + ui.selection as string)
			if ui.text != undefined do append s (" text:\"" + ui.text + "\"")
		)
		"dropdownlist": (
			if ui.items != undefined do append s (" items:" + ui.items as string)
			if ui.selection != undefined do append s (" selection:" + ui.selection as string)
		)
		"radiobuttons": (
			if ui.labels != undefined do append s (" labels:" + ui.labels as string)
			if ui.state  != undefined do append s (" state:" + ui.state as string)
			if ui.useColumns and ui.columns != undefined do append s (" columns:" + ui.columns as string)
			if ui.offsets != undefined do append s (" offsets:" + ui.offsets as string)
		)
		"slider": (
			if ui.range != undefined do append s (" range:" + ui.range as string)
			local t2 = if ui.type != undefined then (ui.type as string) else "float"
			append s (" type:#" + t2)
			if ui.ticks  != undefined do append s (" ticks:" + ui.ticks as string)
			if ui.orient != undefined do append s (" orient:#" + ui.orient as string)
			if ui.controller != undefined do append s (" controller:" + ui.controller as string)
		)
		"angle": (
			if ui.range != undefined do append s (" range:" + ui.range as string)
			if ui.color  != undefined do append s (" color:" + ui.color as string)
			if ui.diameter  != undefined do append s (" diameter:" + ui.diameter as string)
			if ui.degrees   != undefined do append s (" degrees:" + ui.degrees as string)
			if ui.startDegree   != undefined do append s (" startDegree:" + ui.startDegree as string)
			if ui.startRadians  != undefined do append s (" startRadians:" + ui.startRadians as string)
			if ui.dir != undefined do append s (" dir:#" + (ui.dir as string))
		)
		"progressBar": (
			if ui.value  != undefined do append s (" value:" + ui.value as string)
			if ui.color  != undefined do append s (" color:" + ui.color as string)
			if ui.orient != undefined do append s (" orient:#" + ui.orient as string)
		)
		"bitmap": (
			if ui.bitmap   != undefined do append s (" bitmap:" + ui.bitmap as string)
			if ui.filename != undefined do append s (" filename:@\"" + ui.filename + "\"")
		)
		"imgTag": (
			if ui.bitmap    != undefined do append s (" bitmap:" + ui.bitmap as string)
			if ui.opacity   != undefined do append s (" opacity:" + ui.opacity as string)
			-- BUG FIX vs DW: use ui.style correctly, not undefined rdo reference
			if ui.style     != undefined do append s (" style:#" + (ui.style as string))
			if ui.transparent != undefined do append s (" transparent:" + ui.transparent as string)
		)
		"hyperlink": (
			if ui.address      != undefined do append s (" address:@\"" + ui.address + "\"")
			if ui.color        != undefined do append s (" color:" + ui.color as string)
			if ui.hoverColor   != undefined do append s (" hoverColor:" + ui.hoverColor as string)
			if ui.visitedColor != undefined do append s (" visitedColor:" + ui.visitedColor as string)
		)
		"curveControl": (
			-- BUG FIX vs DW: spn_numCurves handler uses val not col
			if ui.numCurves    != undefined do append s (" numCurves:" + ui.numCurves as string)
			if ui.x_range      != undefined do append s (" x_range:" + ui.x_range as string)
			if ui.y_range      != undefined do append s (" y_range:" + ui.y_range as string)
			if ui.x_value      != undefined do append s (" x_value:" + ui.x_value as string)
			if ui.zoomValues   != undefined do append s (" zoomValues:" + ui.zoomValues as string)
			if ui.scrollValues != undefined do append s (" scrollValues:" + ui.scrollValues as string)
			if ui.commandMode  != undefined do append s (" commandMode:#" + (ui.commandMode as string))
			if ui.uiFlags  != undefined do append s (" uiFlags:" + ui.uiFlags as string)
			if ui.rcmFlags != undefined do append s (" rcmFlags:" + ui.rcmFlags as string)
			if ui.asPopup  != undefined do append s (" asPopup:" + ui.asPopup as string)
		)
		"timer": (
			if ui.interval != undefined do append s (" interval:" + ui.interval as string)
			if ui.active   != undefined do append s (" active:" + ui.active as string)
		)
	)
	s
)

fn buildRolloutCode buildUICode:false =
(
	local out = stringstream ""
	format "rollout % \"%\"" newRollout.rolloutName newRollout.rolloutTitle to:out
	format " width:%" newRollout.rolloutWidth to:out
	if newRollout.useHeight do format " height:%" newRollout.rolloutHeight to:out
	if newRollout.bgcolor != undefined do format " bgColor:%" newRollout.bgcolor to:out
	if newRollout.fgcolor != undefined do format " fgColor:%" newRollout.fgcolor to:out
	format "\n(\n" to:out

	for ui in newRollout.controls do
	(
		case ui.controlType of
		(
			"groupstart" : format "\tgroup \"%\"\n\t(\n" ui.label to:out
			"groupend"   : format "\t)\n" to:out
			default:
			(
				local pStr = (buildCommonParamStr ui) + (buildControlParamStr ui)
				if buildUICode then
				(
					if ui.tooltip != "" do append pStr (" tooltip:\"" + (checkString ui.tooltip) + "\"")
				)
				else
					append pStr (" tooltip:\"" + (checkString ui.tooltip) + " (" + ui.controlName + ")\"")
				if ui.comment != "" do append pStr (" --" + ui.comment)
				format "\t% % \"%\"%\n" ui.controlType ui.controlName ui.label pStr to:out
			)
		)
	)

	if buildUICode do
	(
		local hasHandlers = false
		for ui in newRollout.controls do if ui.eventHandlers.count > 0 do hasHandlers = true
		if newRollout.eventHandlers.count > 0 do hasHandlers = true
		if hasHandlers do format "\n" to:out

		for ui in newRollout.controls do
			for eh in ui.eventHandlers do
			(
				if eh.args != "" then
					format "\ton % % % do\n\t(\n%\n\t)\n" ui.controlName eh.event eh.args eh.code to:out
				else
					format "\ton % % do\n\t(\n%\n\t)\n" ui.controlName eh.event eh.code to:out
			)
		for eh in newRollout.eventHandlers do
		(
			if eh.args != "" then
				format "\ton % % % do\n\t(\n%\n\t)\n" newRollout.rolloutName eh.event eh.args eh.code to:out
			else
				format "\ton % % do\n\t(\n%\n\t)\n" newRollout.rolloutName eh.event eh.code to:out
		)
	)

	format ")\n" to:out
	out as string
)

fn buildMacroScriptCode =
(
	local out = stringstream ""
	local cfg = macroScriptConfig
	format "global TOOLS_VERSION = \"%\"\n\n" TOOLS_VERSION to:out
	format "macroScript %\n" cfg.scriptName to:out
	format "\tcategory:\"%\"\n" cfg.category to:out
	if cfg.internalName != "" do format "\tinternalName:\"%\"\n" cfg.internalName to:out
	format "\ttoolTip:\"%\"\n" cfg.toolTip to:out
	format "\tbuttonText:\"%\"\n" cfg.buttonText to:out
	format "(\n" to:out
	format "\ttry(destroyDialog %)catch()\n\n" newRollout.rolloutName to:out
	local rolloutCode = buildRolloutCode buildUICode:true
	for line in filterString rolloutCode "\n" do format "\t%\n" line to:out
	format "\n\tCreateDialog %" newRollout.rolloutName to:out
	if newRollout.style != undefined and newRollout.style.count > 0 do
		format " style:%" (newRollout.style as string) to:out
	if newRollout.lockWidth  do format " lockWidth:true"  to:out
	if newRollout.lockHeight do format " lockHeight:true" to:out
	if newRollout.modal      do format " modal:true"      to:out
	format "\n)\n" to:out
	out as string
)

-- ==============================================================
-- SECTION 7: PARSER  (import existing MAXScript rollout code)
-- ==============================================================

fn parseMAXScriptCode codeStr =
(
	local result  = rolloutConstructor()
	local ss      = codeStr as stringStream
	seek ss 0
	local inGroup = false
	local groupName = ""

	while not eof ss do
	(
		local line = trimLeft (readLine ss)
		if matchPattern line pattern:"--*" do continue
		if line == "" do continue

		case of
		(
			(matchPattern line pattern:"rollout *"): (
				local tss = line as stringStream
				readToken tss
				result.rolloutName  = readToken tss
				result.rolloutTitle = substituteString (readToken tss) "\"" ""
				while (peekToken tss) != undefined do
				(
					local tok = readToken tss
					case of
					(
						(matchPattern tok pattern:"width:*"):
							try(result.rolloutWidth = (filterString tok ":")[2] as integer) catch()
						(matchPattern tok pattern:"height:*"):
						(
							try(result.rolloutHeight = (filterString tok ":")[2] as integer) catch()
							result.useHeight = true
						)
					)
				)
			)
			(matchPattern line pattern:"group *"): (
				local ctrl = UIControlStruct()
				ctrl.controlType = "groupstart"
				ctrl.controlName = "grp_" + ((for o in result.controls where o.controlType=="groupstart" collect o).count + 1) as string
				local tss2 = line as stringStream
				readToken tss2
				ctrl.label = substituteString (readToken tss2) "\"" ""
				inGroup    = true
				groupName  = ctrl.controlName
				append result.controls ctrl
			)
			(matchPattern line pattern:")*"): (
				if inGroup do
				(
					local ctrl     = UIControlStruct()
					ctrl.controlType = "groupend"
					ctrl.controlName = groupName
					inGroup = false
					append result.controls ctrl
				)
			)
			(matchPattern line pattern:"on * *"): ()
			default: (
				local knownTypes = #("label","spinner","checkbox","button","checkbutton",
					"pickbutton","mapbutton","materialbutton","dropdownlist","listbox",
					"multilistbox","combobox","radiobuttons","edittext","colorpicker",
					"slider","angle","bitmap","imgTag","subRollout","hyperlink",
					"curveControl","progressBar","groupbox","timer")
				for ct in knownTypes do
				(
					if matchPattern line pattern:(ct + " *") do
					(
						local ctrl = UIControlStruct()
						local tss3 = line as stringStream
						ctrl.controlType = readToken tss3
						ctrl.controlName = readToken tss3
						if matchPattern line pattern:("* " + ctrl.controlName + " \"*") do
							ctrl.label = substituteString (readToken tss3) "\"" ""
						while (peekToken tss3) != undefined do
						(
							local tok = readToken tss3
							if matchPattern tok pattern:"*:*" do
							(
								local parts = filterString tok ":"
								if parts.count >= 2 do
								(
									local key = toLower parts[1]
									local val = parts[2]
									case key of
									(
										"width":      (ctrl.useWidth=true;  try(ctrl.width=val as integer)catch())
										"height":     (ctrl.useHeight=true; try(ctrl.height=val as integer)catch())
										"across":     (ctrl.useAcross=true; try(ctrl.across=val as integer)catch())
										"checked":    (try(ctrl.checked=execute val)catch())
										"items":      (try(ctrl.items=execute val)catch())
										"labels":     (try(ctrl.labels=execute val)catch())
										"range":      (try(ctrl.range=execute val)catch())
										"type":       (ctrl.type=substituteString val "#" "")
										"selection":  (try(ctrl.selection=val as integer)catch())
										"text":       (ctrl.text=substituteString val "\"" "")
										"tooltip":    (ctrl.tooltip=substituteString val "\"" "")
										"enabled":    (try(ctrl.enabled=execute val)catch())
										"visible":    (ctrl.useVisible=true; try(ctrl.visible=execute val)catch())
										"align":      (ctrl.useAlign=true; try(ctrl.align=execute val)catch())
										"color":      (try(ctrl.color=execute val)catch())
										"fieldwidth": (ctrl.useFieldWidth=true; try(ctrl.fieldWidth=val as integer)catch())
									)
								)
							)
						)
						local existing = for o in result.controls collect o.controlName
						local base = ctrl.controlName; local n = 2
						while findItem existing ctrl.controlName != 0 do
						( ctrl.controlName = base + "_" + n as string; n += 1 )
						append result.controls ctrl
						exit
					)
				)
			)
		)
	)
	result
)

-- ==============================================================
-- SECTION 8: LIVE PREVIEW
-- ==============================================================

fn refreshPreview =
(
	try(destroyDialog RL_Preview) catch()
	local rci
	if not newRollout.useHeight then
		rci = rolloutCreator newRollout.rolloutName newRollout.rolloutTitle width:newRollout.rolloutWidth
	else
		rci = rolloutCreator newRollout.rolloutName newRollout.rolloutTitle width:newRollout.rolloutWidth height:newRollout.rolloutHeight
	rci.begin()
	for ui in newRollout.controls do
	(
		case ui.controlType of
		(
			"groupstart" : rci.addText ("group @" + ui.label + "@\n(") filter:true
			"groupend"   : rci.addText ")" filter:true
			default: (
				local pStr = (buildCommonParamStr ui) + (buildControlParamStr ui)
				append pStr (" tooltip:\"" + (checkString ui.tooltip) + " (" + ui.controlName + ")\"")
				try(rci.addControl (ui.controlType as name) ui.controlName ui.label paramStr:pStr) catch()
			)
		)
	)
	global RL_Preview = rci.end()
	local pos = [750, 100]
	if RL_GUIEditor != undefined do
	(
		local mp = getDialogPos RL_GUIEditor
		pos = [mp.x + 760, mp.y]
	)
	local cmd = stringstream ""
	format "createDialog RL_Preview pos:[%,%]" pos.x pos.y to:cmd
	if newRollout.style != undefined and newRollout.style.count > 0 do
		format " style:%" (newRollout.style as string) to:cmd
	if newRollout.bgcolor != undefined do format " bgColor:%" newRollout.bgcolor to:cmd
	if newRollout.fgcolor != undefined do format " fgColor:%" newRollout.fgcolor to:cmd
	if newRollout.lockWidth  do format " lockWidth:true"  to:cmd
	if newRollout.lockHeight do format " lockHeight:true" to:cmd
	execute (cmd as string)
	gc light:true
)

-- ==============================================================
-- SECTION 9: DEFAULT CONTROL FACTORY
-- ==============================================================

fn makeDefaultControl type =
(
	local ctrl = UIControlStruct controlType:type
	case type of
	(
		"label"         : (ctrl.controlName="lbl_"; ctrl.label="Label")
		"button"        : (ctrl.controlName="btn_"; ctrl.label="Button";        ctrl.useWidth=true; ctrl.width=140)
		"checkbutton"   : (ctrl.controlName="cbt_"; ctrl.label="CheckButton";   ctrl.useWidth=true; ctrl.width=140)
		"pickbutton"    : (ctrl.controlName="pbt_"; ctrl.label="Pick Object";   ctrl.useWidth=true; ctrl.width=140)
		"mapbutton"     : (ctrl.controlName="mbt_"; ctrl.label="Map Button";    ctrl.useWidth=true; ctrl.width=140)
		"materialbutton": (ctrl.controlName="xbt_"; ctrl.label="Material";      ctrl.useWidth=true; ctrl.width=140)
		"spinner"       : (ctrl.controlName="spn_"; ctrl.label="Value";         ctrl.range=[0,100,1]; ctrl.type="float")
		"checkbox"      : (ctrl.controlName="chk_"; ctrl.label="Option";        ctrl.checked=false)
		"colorpicker"   : (ctrl.controlName="cpl_"; ctrl.label="Color";         ctrl.color=(color 128 128 128))
		"edittext"      : (ctrl.controlName="edt_"; ctrl.label="Text";          ctrl.text="")
		"dropdownlist"  : (ctrl.controlName="ddl_"; ctrl.label="Select";        ctrl.items=#("Item A","Item B","Item C"))
		"listbox"       : (ctrl.controlName="lbx_"; ctrl.label="List";          ctrl.items=#("Item A","Item B"); ctrl.useHeight=true; ctrl.height=60)
		"multilistbox"  : (ctrl.controlName="mlb_"; ctrl.label="Multi List";    ctrl.items=#("Item A","Item B"); ctrl.useHeight=true; ctrl.height=60)
		"combobox"      : (ctrl.controlName="cbo_"; ctrl.label="Combo";         ctrl.items=#("Item A","Item B"))
		"radiobuttons"  : (ctrl.controlName="rdo_"; ctrl.label="Options";       ctrl.labels=#("A","B","C"); ctrl.state=1)
		"slider"        : (ctrl.controlName="sld_"; ctrl.label="Slider";        ctrl.range=[0,100,50]; ctrl.type="float")
		"angle"         : (ctrl.controlName="ang_"; ctrl.label="Angle";         ctrl.range=[0,360,0])
		"progressBar"   : (ctrl.controlName="prg_"; ctrl.label="Progress";      ctrl.value=50; ctrl.useWidth=true; ctrl.width=140)
		"bitmap"        : (ctrl.controlName="bmp_"; ctrl.label="Bitmap")
		"imgTag"        : (ctrl.controlName="img_"; ctrl.label="Image")
		"hyperlink"     : (ctrl.controlName="hyp_"; ctrl.label="Link";          ctrl.address="http://")
		"curveControl"  : (ctrl.controlName="cc_";  ctrl.label="Curve";         ctrl.useWidth=true; ctrl.width=200; ctrl.useHeight=true; ctrl.height=100)
		"groupbox"      : (ctrl.controlName="gbx_"; ctrl.label="Group")
		"subRollout"    : (ctrl.controlName="sub_"; ctrl.label="SubRollout";    ctrl.useHeight=true; ctrl.height=100)
		"timer"         : (ctrl.controlName="tmr_"; ctrl.label="Timer";         ctrl.interval=1000; ctrl.active=false)
		"groupstart"    : (ctrl.controlName="grp_"; ctrl.label="Group")
		"groupend"      : (ctrl.controlName="grp_"; ctrl.label="")
	)
	ctrl
)

fn addControlToRollout type =
(
	pushUndo()
	local ctrl = makeDefaultControl type
	if type != "groupstart" and type != "groupend" do
		ctrl.controlName = getUniqueControlName ctrl.controlName
	local pos = newRollout.activeControl + 1
	if pos < 1 do pos = 1
	if pos > newRollout.controls.count + 1 do pos = newRollout.controls.count + 1
	insertItem ctrl newRollout.controls pos
	newRollout.activeControl = pos
)

-- ==============================================================
-- SECTION 10: TYPE-SPECIFIC PROPERTY PANELS
-- ==============================================================

rollout RL_PropNone "(No extra properties)" (
	label lbl_ "No additional properties\nfor this control type." align:#center
)

rollout RL_PropSpinner "Spinner" (
	group "Range" (
		spinner spn_from "From" type:#float range:[-1e9,1e9,0]   across:3 fieldWidth:58
		spinner spn_to   "To"   type:#float range:[-1e9,1e9,100] fieldWidth:58
		spinner spn_val  "Val"  type:#float range:[-1e9,1e9,1]   fieldWidth:58
	)
	radiobuttons rdo_type "Type" labels:#("Float","Integer","WorldUnits") columns:3 align:#left
	checkbox chk_fw "Field Width" across:2
	spinner spn_fw "" type:#integer range:[0,500,45] fieldWidth:55 enabled:false
	checkbox chk_indet "Indeterminate" across:2
	checkbox chk_skb "Set Key Brackets"
	edittext edt_ctrl "Controller" labelOnTop:true

	fn load = (
		local ui = newRollout.controls[newRollout.activeControl]
		if ui.range != undefined do ( spn_from.value=ui.range[1]; spn_to.value=ui.range[2]; spn_val.value=ui.range[3] )
		rdo_type.state = case (if ui.type!=undefined then (ui.type as string) else "float") of ("float":1;"integer":2;"worldUnits":3;default:1)
		chk_fw.checked=ui.useFieldWidth; spn_fw.enabled=ui.useFieldWidth; spn_fw.value=ui.fieldWidth
		if ui.indeterminate  != undefined do chk_indet.checked=ui.indeterminate
		if ui.setKeyBrackets != undefined do chk_skb.checked=ui.setKeyBrackets
		if ui.controller     != undefined do edt_ctrl.text=ui.controller
	)
	on RL_PropSpinner open do load()
	on spn_from changed val do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,100,1]
		newRollout.controls[newRollout.activeControl].range[1]=val; refreshPreview()
	)
	on spn_to   changed val do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,100,1]
		newRollout.controls[newRollout.activeControl].range[2]=val; refreshPreview()
	)
	on spn_val  changed val do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,100,1]
		newRollout.controls[newRollout.activeControl].range[3]=val; refreshPreview()
	)
	on rdo_type  changed s do ( newRollout.controls[newRollout.activeControl].type=case s of(1:"float";2:"integer";3:"worldUnits";default:"float"); refreshPreview() )
	on chk_fw    changed s do ( newRollout.controls[newRollout.activeControl].useFieldWidth=spn_fw.enabled=s; refreshPreview() )
	on spn_fw    changed v do ( newRollout.controls[newRollout.activeControl].fieldWidth=v; refreshPreview() )
	on chk_indet changed s do ( newRollout.controls[newRollout.activeControl].indeterminate=s; refreshPreview() )
	on chk_skb   changed s do ( newRollout.controls[newRollout.activeControl].setKeyBrackets=s; refreshPreview() )
	on edt_ctrl  entered text do ( newRollout.controls[newRollout.activeControl].controller=if text==""then undefined else text )
)

rollout RL_PropCheckbox "Checkbox" (
	checkbox chk_chk "Checked" across:2
	checkbox chk_tri "Use TriState"
	spinner  spn_tri "TriState" type:#integer range:[0,2,0] fieldWidth:50
	on RL_PropCheckbox open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.checked   !=undefined do chk_chk.checked=ui.checked
		if ui.useTriState!=undefined do chk_tri.checked=ui.useTriState
		if ui.triState  !=undefined do spn_tri.value=ui.triState
	)
	on chk_chk changed s do ( newRollout.controls[newRollout.activeControl].checked=s; refreshPreview() )
	on chk_tri changed s do ( newRollout.controls[newRollout.activeControl].useTriState=s; refreshPreview() )
	on spn_tri changed v do ( newRollout.controls[newRollout.activeControl].triState=v; refreshPreview() )
)

rollout RL_PropButton "Button" (
	checkbox chk_border "Show Border" checked:true
	on RL_PropButton open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.border!=undefined do chk_border.checked=ui.border
	)
	on chk_border changed s do ( newRollout.controls[newRollout.activeControl].border=s; refreshPreview() )
)

rollout RL_PropCheckbutton "CheckButton" (
	colorpicker cpl_hl "Highlight Color" align:#right
	checkbox    chk_chk "Checked"
	on RL_PropCheckbutton open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.highlightColor!=undefined do cpl_hl.color=ui.highlightColor
		if ui.checked!=undefined do chk_chk.checked=ui.checked
	)
	on cpl_hl changed col do ( newRollout.controls[newRollout.activeControl].highlightColor=col; refreshPreview() )
	on chk_chk changed s  do ( newRollout.controls[newRollout.activeControl].checked=s; refreshPreview() )
)

rollout RL_PropPickbutton "PickButton" (
	edittext edt_msg "Message" labelOnTop:true
	edittext edt_flt "Filter"  labelOnTop:true
	checkbox chk_ad  "Auto Display"
	on RL_PropPickbutton open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.message   !=undefined do edt_msg.text=ui.message
		if ui.filter    !=undefined do edt_flt.text=ui.filter
		if ui.autoDisplay!=undefined do chk_ad.checked=ui.autoDisplay
	)
	on edt_msg entered text do ( newRollout.controls[newRollout.activeControl].message=if text==""then undefined else text )
	on edt_flt entered text do ( newRollout.controls[newRollout.activeControl].filter=if text==""then undefined else text )
	on chk_ad  changed s    do ( newRollout.controls[newRollout.activeControl].autoDisplay=s )
)

rollout RL_PropEdittext "Edittext" (
	edittext edt_txt "Default Text" labelOnTop:true
	checkbox chk_lot  "Label On Top" across:3
	checkbox chk_bold "Bold"
	checkbox chk_ro   "Read Only"
	checkbox chk_fw   "Field Width" across:2
	spinner  spn_fw   "" type:#integer range:[0,500,140] fieldWidth:55
	on RL_PropEdittext open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.text     !=undefined do edt_txt.text=ui.text
		if ui.labelOnTop!=undefined do chk_lot.checked=ui.labelOnTop
		if ui.bold     !=undefined do chk_bold.checked=ui.bold
		if ui.readOnly !=undefined do chk_ro.checked=ui.readOnly
		chk_fw.checked=ui.useFieldWidth; spn_fw.value=ui.fieldWidth
	)
	on edt_txt  entered text do ( newRollout.controls[newRollout.activeControl].text=text; refreshPreview() )
	on chk_lot  changed s   do ( newRollout.controls[newRollout.activeControl].labelOnTop=s; refreshPreview() )
	on chk_bold changed s   do ( newRollout.controls[newRollout.activeControl].bold=s; refreshPreview() )
	on chk_ro   changed s   do ( newRollout.controls[newRollout.activeControl].readOnly=s; refreshPreview() )
	on chk_fw   changed s   do ( newRollout.controls[newRollout.activeControl].useFieldWidth=s; refreshPreview() )
	on spn_fw   changed v   do ( newRollout.controls[newRollout.activeControl].fieldWidth=v; refreshPreview() )
)

rollout RL_PropListItems "Listbox / MultiListbox" (
	listbox  lbx_items "Items" height:5
	edittext edt_new   "New Item"
	button btn_add "Add"    across:4 width:80
	button btn_rem "Remove" width:80
	button btn_up  "Up"     width:80
	button btn_dn  "Down"   width:80
	spinner spn_sel "Selection" type:#integer range:[0,200,0]
	checkbox chk_ro "Read Only"

	fn getUI = newRollout.controls[newRollout.activeControl]
	fn syncList = ( lbx_items.items = if (getUI()).items!=undefined then (getUI()).items else #() )
	on RL_PropListItems open do (
		syncList()
		local ui=getUI()
		if ui.selection!=undefined do spn_sel.value=ui.selection
		if ui.readOnly !=undefined do chk_ro.checked=ui.readOnly
	)
	on btn_add pressed do (
		if edt_new.text!="" do (
			local ui=getUI()
			if ui.items==undefined do ui.items=#()
			append ui.items edt_new.text; syncList(); refreshPreview()
		)
	)
	on btn_rem pressed do (
		if lbx_items.selection>0 do (
			-- BUG FIX vs DW: always delete from .items
			deleteItem (getUI()).items lbx_items.selection; syncList(); refreshPreview()
		)
	)
	on btn_up pressed do (
		local ui=getUI(); local sel=lbx_items.selection
		if sel>1 and ui.items!=undefined do (
			swap ui.items[sel] ui.items[sel-1]; syncList(); lbx_items.selection=sel-1; refreshPreview()
		)
	)
	on btn_dn pressed do (
		local ui=getUI(); local sel=lbx_items.selection
		if sel>0 and sel<lbx_items.items.count and ui.items!=undefined do (
			swap ui.items[sel] ui.items[sel+1]; syncList(); lbx_items.selection=sel+1; refreshPreview()
		)
	)
	on spn_sel changed v do ( getUI().selection=v; refreshPreview() )
	on chk_ro  changed s do ( getUI().readOnly=s; refreshPreview() )
)

rollout RL_PropItems "Dropdown / Combobox" (
	listbox  lbx_items "Items" height:5
	edittext edt_new   "New Item"
	button btn_add "Add"    across:4 width:80
	button btn_rem "Remove" width:80
	button btn_up  "Up"     width:80
	button btn_dn  "Down"   width:80
	spinner spn_sel "Selection" type:#integer range:[0,200,0]

	fn getUI = newRollout.controls[newRollout.activeControl]
	fn syncList = ( lbx_items.items = if (getUI()).items!=undefined then (getUI()).items else #() )
	on RL_PropItems open do ( syncList(); local ui=getUI(); if ui.selection!=undefined do spn_sel.value=ui.selection )
	on btn_add pressed do (
		if edt_new.text!="" do (
			local ui=getUI()
			if ui.items==undefined do ui.items=#()
			append ui.items edt_new.text; syncList(); refreshPreview()
		)
	)
	on btn_rem pressed do (
		-- BUG FIX vs DW: delete from .items not .labels
		if lbx_items.selection>0 do (
			deleteItem (getUI()).items lbx_items.selection; syncList(); refreshPreview()
		)
	)
	on btn_up pressed do (
		local ui=getUI(); local sel=lbx_items.selection
		if sel>1 and ui.items!=undefined do (
			swap ui.items[sel] ui.items[sel-1]; syncList(); lbx_items.selection=sel-1; refreshPreview()
		)
	)
	on btn_dn pressed do (
		local ui=getUI(); local sel=lbx_items.selection
		if sel>0 and sel<lbx_items.items.count and ui.items!=undefined do (
			swap ui.items[sel] ui.items[sel+1]; syncList(); lbx_items.selection=sel+1; refreshPreview()
		)
	)
	on spn_sel changed v do ( getUI().selection=v; refreshPreview() )
)

rollout RL_PropRadiobuttons "Radiobuttons" (
	listbox  lbx_lbls "Labels" height:5
	edittext edt_new  "New Label"
	button btn_add "Add"    across:4 width:80
	button btn_rem "Remove" width:80
	button btn_up  "Up"     width:80
	button btn_dn  "Down"   width:80
	spinner  spn_state "State" type:#integer range:[0,50,1]
	checkbox chk_cols "Columns" across:2
	spinner  spn_cols "" type:#integer range:[1,10,2] fieldWidth:40 enabled:false

	fn getUI = newRollout.controls[newRollout.activeControl]
	fn syncList = ( lbx_lbls.items = if (getUI()).labels!=undefined then (getUI()).labels else #() )
	on RL_PropRadiobuttons open do (
		syncList()
		local ui=getUI()
		if ui.state    !=undefined do spn_state.value=ui.state
		if ui.useColumns!=undefined do chk_cols.checked=ui.useColumns
		if ui.columns  !=undefined do spn_cols.value=ui.columns
		spn_cols.enabled=chk_cols.checked
	)
	on btn_add pressed do (
		if edt_new.text!="" do (
			local ui=getUI()
			if ui.labels==undefined do ui.labels=#()
			append ui.labels edt_new.text; syncList(); refreshPreview()
		)
	)
	on btn_rem pressed do (
		if lbx_lbls.selection>0 do (
			deleteItem (getUI()).labels lbx_lbls.selection; syncList(); refreshPreview()
		)
	)
	on btn_up pressed do (
		local ui=getUI(); local sel=lbx_lbls.selection
		if sel>1 and ui.labels!=undefined do (
			swap ui.labels[sel] ui.labels[sel-1]; syncList(); lbx_lbls.selection=sel-1; refreshPreview()
		)
	)
	on btn_dn pressed do (
		local ui=getUI(); local sel=lbx_lbls.selection
		if sel>0 and sel<lbx_lbls.items.count and ui.labels!=undefined do (
			swap ui.labels[sel] ui.labels[sel+1]; syncList(); lbx_lbls.selection=sel+1; refreshPreview()
		)
	)
	on spn_state changed v do ( getUI().state=v; refreshPreview() )
	on chk_cols  changed s do ( getUI().useColumns=spn_cols.enabled=s; getUI().columns=spn_cols.value; refreshPreview() )
	on spn_cols  changed v do ( getUI().columns=v; refreshPreview() )
)

rollout RL_PropColorpicker "ColorPicker" (
	colorpicker cpl_col "Default Color" align:#right
	checkbox chk_alpha "Alpha" across:2
	checkbox chk_modal "Modal"
	edittext edt_title "Title"
	checkbox chk_fw "Field Width" across:2
	spinner  spn_fw "" type:#integer range:[0,300,40] fieldWidth:50 enabled:false
	on RL_PropColorpicker open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.color!=undefined do cpl_col.color=ui.color
		if ui.alpha!=undefined do chk_alpha.checked=ui.alpha
		if ui.modal!=undefined do chk_modal.checked=ui.modal
		if ui.title!=undefined do edt_title.text=ui.title
		chk_fw.checked=ui.useFieldWidth; spn_fw.enabled=ui.useFieldWidth; spn_fw.value=ui.fieldWidth
	)
	on cpl_col   changed col do ( newRollout.controls[newRollout.activeControl].color=col; refreshPreview() )
	on chk_alpha changed s   do ( newRollout.controls[newRollout.activeControl].alpha=s; refreshPreview() )
	on chk_modal changed s   do ( newRollout.controls[newRollout.activeControl].modal=s; refreshPreview() )
	on edt_title entered text do ( newRollout.controls[newRollout.activeControl].title=if text==""then undefined else text )
	on chk_fw    changed s   do ( newRollout.controls[newRollout.activeControl].useFieldWidth=spn_fw.enabled=s; refreshPreview() )
	on spn_fw    changed v   do ( newRollout.controls[newRollout.activeControl].fieldWidth=v; refreshPreview() )
)

rollout RL_PropSlider "Slider" (
	group "Range" (
		spinner spn_from "From" type:#float range:[-1e9,1e9,0]   across:3 fieldWidth:58
		spinner spn_to   "To"   type:#float range:[-1e9,1e9,100] fieldWidth:58
		spinner spn_val  "Val"  type:#float range:[-1e9,1e9,50]  fieldWidth:58
		spinner spn_ticks "Ticks" type:#integer range:[0,100,5]
	)
	radiobuttons rdo_type   "Type"   labels:#("Float","Integer")         columns:2
	radiobuttons rdo_orient "Orient" labels:#("Horizontal","Vertical")   columns:2
	on RL_PropSlider open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.range!=undefined do ( spn_from.value=ui.range[1]; spn_to.value=ui.range[2]; spn_val.value=ui.range[3] )
		if ui.ticks!=undefined do spn_ticks.value=ui.ticks
		rdo_type.state  =if (ui.type   as string)=="integer"  then 2 else 1
		rdo_orient.state=if (ui.orient as string)=="vertical" then 2 else 1
	)
	on spn_from  changed v do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,100,50]
		newRollout.controls[newRollout.activeControl].range[1]=v; refreshPreview()
	)
	on spn_to    changed v do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,100,50]
		newRollout.controls[newRollout.activeControl].range[2]=v; refreshPreview()
	)
	on spn_val   changed v do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,100,50]
		newRollout.controls[newRollout.activeControl].range[3]=v; refreshPreview()
	)
	on spn_ticks  changed v do ( newRollout.controls[newRollout.activeControl].ticks=v; refreshPreview() )
	on rdo_type   changed s do ( newRollout.controls[newRollout.activeControl].type=if s==2 then "integer" else "float"; refreshPreview() )
	on rdo_orient changed s do ( newRollout.controls[newRollout.activeControl].orient=if s==2 then "vertical" else "horizontal"; refreshPreview() )
)

rollout RL_PropAngle "Angle" (
	group "Range" (
		spinner spn_from "From" type:#float range:[0,360,0]   across:3 fieldWidth:55
		spinner spn_to   "To"   type:#float range:[0,360,360] fieldWidth:55
		spinner spn_val  "Val"  type:#float range:[0,360,0]   fieldWidth:55
		spinner spn_diam "Diameter" type:#integer range:[10,500,64]
	)
	colorpicker cpl_col "Color" align:#right
	radiobuttons rdo_dir "Direction" labels:#("CW","CCW") columns:2
	on RL_PropAngle open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.range   !=undefined do ( spn_from.value=ui.range[1]; spn_to.value=ui.range[2]; spn_val.value=ui.range[3] )
		if ui.diameter!=undefined do spn_diam.value=ui.diameter
		if ui.color   !=undefined do cpl_col.color=ui.color
		rdo_dir.state=if (ui.dir as string)=="ccw" then 2 else 1
	)
	on spn_from changed v do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,360,0]
		newRollout.controls[newRollout.activeControl].range[1]=v; refreshPreview()
	)
	on spn_to   changed v do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,360,0]
		newRollout.controls[newRollout.activeControl].range[2]=v; refreshPreview()
	)
	on spn_val  changed v do (
		if newRollout.controls[newRollout.activeControl].range==undefined do newRollout.controls[newRollout.activeControl].range=[0,360,0]
		newRollout.controls[newRollout.activeControl].range[3]=v; refreshPreview()
	)
	on spn_diam changed v do ( newRollout.controls[newRollout.activeControl].diameter=v; refreshPreview() )
	on cpl_col  changed col do ( newRollout.controls[newRollout.activeControl].color=col; refreshPreview() )
	on rdo_dir  changed s do ( newRollout.controls[newRollout.activeControl].dir=if s==2 then #ccw else #cw; refreshPreview() )
)

rollout RL_PropHyperlink "Hyperlink" (
	edittext    edt_addr  "URL"           labelOnTop:true
	colorpicker cpl_col   "Color"         align:#right
	colorpicker cpl_hover "Hover Color"   align:#right
	colorpicker cpl_visit "Visited Color" align:#right
	on RL_PropHyperlink open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.address    !=undefined do edt_addr.text=ui.address
		if ui.color      !=undefined do cpl_col.color=ui.color
		if ui.hoverColor !=undefined do cpl_hover.color=ui.hoverColor
		if ui.visitedColor!=undefined do cpl_visit.color=ui.visitedColor
	)
	on edt_addr  entered text do ( newRollout.controls[newRollout.activeControl].address=text; refreshPreview() )
	on cpl_col   changed col  do ( newRollout.controls[newRollout.activeControl].color=col; refreshPreview() )
	on cpl_hover changed col  do ( newRollout.controls[newRollout.activeControl].hoverColor=col; refreshPreview() )
	on cpl_visit changed col  do ( newRollout.controls[newRollout.activeControl].visitedColor=col; refreshPreview() )
)

rollout RL_PropProgressbar "ProgressBar" (
	spinner     spn_val "Value" type:#float range:[0,100,50]
	colorpicker cpl_col "Color" align:#right
	radiobuttons rdo_orient "Orient" labels:#("Horizontal","Vertical") columns:2
	on RL_PropProgressbar open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.value !=undefined do spn_val.value=ui.value
		if ui.color !=undefined do cpl_col.color=ui.color
		rdo_orient.state=if (ui.orient as string)=="vertical" then 2 else 1
	)
	on spn_val   changed v   do ( newRollout.controls[newRollout.activeControl].value=v; refreshPreview() )
	on cpl_col   changed col do ( newRollout.controls[newRollout.activeControl].color=col; refreshPreview() )
	on rdo_orient changed s  do ( newRollout.controls[newRollout.activeControl].orient=if s==2 then "vertical" else "horizontal"; refreshPreview() )
)

rollout RL_PropTimer "Timer" (
	spinner  spn_int "Interval (ms)" type:#integer range:[1,100000,1000]
	checkbox chk_act "Active on Open"
	on RL_PropTimer open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.interval!=undefined do spn_int.value=ui.interval
		if ui.active  !=undefined do chk_act.checked=ui.active
	)
	on spn_int changed v do ( newRollout.controls[newRollout.activeControl].interval=v )
	on chk_act changed s do ( newRollout.controls[newRollout.activeControl].active=s )
)

rollout RL_PropBitmap "Bitmap" (
	edittext edt_var  "Variable Name"
	edittext edt_path "File Path" labelOnTop:true
	button   btn_browse "Browse..." width:200 align:#right
	on RL_PropBitmap open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.bitmap  !=undefined do edt_var.text=ui.bitmap
		if ui.filename!=undefined do edt_path.text=ui.filename
	)
	on edt_var  entered text do ( newRollout.controls[newRollout.activeControl].bitmap=if text==""then undefined else text )
	on edt_path entered text do ( newRollout.controls[newRollout.activeControl].filename=if text==""then undefined else text )
	on btn_browse pressed do (
		local f=getOpenFileName types:"Bitmap|*.bmp;*.png;*.jpg;*.tif|All|*.*|"
		if f!=undefined do ( edt_path.text=f; newRollout.controls[newRollout.activeControl].filename=f; refreshPreview() )
	)
)

rollout RL_PropImgTag "ImgTag" (
	edittext     edt_bmp "Bitmap Variable"
	spinner      spn_opa "Opacity" type:#float range:[0,100,100]
	radiobuttons rdo_sty "Style" labels:#("Stretch","Tile","Center") columns:3
	colorpicker  cpl_tra "Transparent Color" align:#right
	on RL_PropImgTag open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.bitmap   !=undefined do edt_bmp.text=ui.bitmap
		if ui.opacity  !=undefined do spn_opa.value=ui.opacity
		-- BUG FIX vs DW: correctly map style to radio state
		if ui.style!=undefined do
			rdo_sty.state=findItem #("bmp_stretch","bmp_tile","bmp_center") (ui.style as string)
		if ui.transparent!=undefined do cpl_tra.color=ui.transparent
	)
	on edt_bmp  entered text do ( newRollout.controls[newRollout.activeControl].bitmap=if text==""then undefined else text; refreshPreview() )
	on spn_opa  changed v   do ( newRollout.controls[newRollout.activeControl].opacity=v; refreshPreview() )
	on rdo_sty  changed s   do (
		newRollout.controls[newRollout.activeControl].style=case s of(1:#bmp_stretch;2:#bmp_tile;3:#bmp_center;default:#bmp_stretch)
		refreshPreview()
	)
	on cpl_tra changed col do ( newRollout.controls[newRollout.activeControl].transparent=col; refreshPreview() )
)

rollout RL_PropLabel "Label" (
	checkbox chk_se "Sunken Edge"
	on RL_PropLabel open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.style_sunkenEdge!=undefined do chk_se.checked=ui.style_sunkenEdge
	)
	on chk_se changed s do ( newRollout.controls[newRollout.activeControl].style_sunkenEdge=s; refreshPreview() )
)

rollout RL_PropMapButton "Map / Material Button" (
	checkbox chk_border "Show Border" checked:true
	on RL_PropMapButton open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.border!=undefined do chk_border.checked=ui.border
	)
	on chk_border changed s do ( newRollout.controls[newRollout.activeControl].border=s; refreshPreview() )
)

rollout RL_PropCurveControl "CurveControl" (
	-- BUG FIX vs DW: uses val not col in numCurves handler
	spinner spn_nc "Num Curves" type:#integer range:[1,20,1]
	group "X Range" (
		spinner spn_xf "From" across:2 type:#float range:[-1e9,1e9,0] fieldWidth:58
		spinner spn_xt "To"   type:#float range:[-1e9,1e9,1]          fieldWidth:58
	)
	group "Y Range" (
		spinner spn_yf "From" across:2 type:#float range:[-1e9,1e9,0] fieldWidth:58
		spinner spn_yt "To"   type:#float range:[-1e9,1e9,1]          fieldWidth:58
	)
	checkbox chk_pop "As Popup"
	on RL_PropCurveControl open do (
		local ui=newRollout.controls[newRollout.activeControl]
		if ui.numCurves!=undefined do spn_nc.value=ui.numCurves
		if ui.x_range!=undefined do ( spn_xf.value=ui.x_range[1]; spn_xt.value=ui.x_range[2] )
		if ui.y_range!=undefined do ( spn_yf.value=ui.y_range[1]; spn_yt.value=ui.y_range[2] )
		if ui.asPopup!=undefined do chk_pop.checked=ui.asPopup
	)
	on spn_nc  changed val do ( newRollout.controls[newRollout.activeControl].numCurves=val )  -- BUG FIX: val not col
	on spn_xf  changed v do (
		if newRollout.controls[newRollout.activeControl].x_range==undefined do newRollout.controls[newRollout.activeControl].x_range=[0,1]
		newRollout.controls[newRollout.activeControl].x_range[1]=v
	)
	on spn_xt  changed v do (
		if newRollout.controls[newRollout.activeControl].x_range==undefined do newRollout.controls[newRollout.activeControl].x_range=[0,1]
		newRollout.controls[newRollout.activeControl].x_range[2]=v
	)
	on spn_yf  changed v do (
		if newRollout.controls[newRollout.activeControl].y_range==undefined do newRollout.controls[newRollout.activeControl].y_range=[0,1]
		newRollout.controls[newRollout.activeControl].y_range[1]=v
	)
	on spn_yt  changed v do (
		if newRollout.controls[newRollout.activeControl].y_range==undefined do newRollout.controls[newRollout.activeControl].y_range=[0,1]
		newRollout.controls[newRollout.activeControl].y_range[2]=v
	)
	on chk_pop changed s do ( newRollout.controls[newRollout.activeControl].asPopup=s )
)

-- ==============================================================
-- SECTION 11: COMMON PARAMETERS PANEL
-- ==============================================================

rollout RL_CommonParams "Common Parameters" (
	label lbl_type "Type:"  across:2 align:#left offset:[0,3]
	label lbl_tv   ""       align:#left
	label lbl_n    "Name:"  across:2 align:#left offset:[0,3]
	edittext edt_n "" fieldWidth:162
	label lbl_l    "Label:" across:2 align:#left offset:[0,3]
	edittext edt_l "" fieldWidth:162

	group "Layout" (
		checkbox chk_en  "Enabled" checked:true across:2
		checkbox chk_vis "Visible"

		checkbox chk_w "Width" across:3 align:#left
		spinner  spn_w "" type:#integer range:[0,2000,100] fieldWidth:50 enabled:false
		button   btn_fw "100%" width:42

		checkbox chk_pct "% Width" across:2 align:#left
		spinner  spn_pct "" type:#float range:[1,100,50] fieldWidth:50 enabled:false

		checkbox chk_h "Height" across:2 align:#left
		spinner  spn_h "" type:#integer range:[0,2000,50] fieldWidth:50 enabled:false

		checkbox chk_ac "Across" across:2 align:#left
		spinner  spn_ac "" type:#integer range:[1,20,2] fieldWidth:50 enabled:false

		checkbox chk_al "Align" align:#left
		radiobuttons rdo_al "" labels:#("Left","Center","Right") columns:3 align:#left enabled:false

		checkbox chk_off "Offset" across:3 align:#left
		spinner spn_ox "X" type:#integer range:[-500,500,0] fieldWidth:45 enabled:false
		spinner spn_oy "Y" type:#integer range:[-500,500,0] fieldWidth:45 enabled:false

		checkbox chk_pos "Pos" across:3 align:#left
		spinner spn_px "X" type:#integer range:[0,2000,0] fieldWidth:45 enabled:false
		spinner spn_py "Y" type:#integer range:[0,2000,0] fieldWidth:45 enabled:false
	)
	edittext edt_tip "Tooltip"  labelOnTop:true
	edittext edt_cmt "Comment"  labelOnTop:true

	fn load = (
		local sel=newRollout.activeControl
		if sel==0 or sel>newRollout.controls.count do return undefined
		local ui=newRollout.controls[sel]
		lbl_tv.text = ui.controlType
		edt_n.text  = ui.controlName
		edt_l.text  = ui.label
		chk_en.checked  = if ui.enabled!=undefined then ui.enabled else true
		chk_vis.checked = ui.useVisible
		chk_w.checked   = ui.useWidth;   spn_w.enabled=ui.useWidth;   spn_w.value=ui.width
		chk_pct.checked = ui.usePercentageWidth; spn_pct.enabled=ui.usePercentageWidth; spn_pct.value=ui.percentageWidth
		chk_h.checked   = ui.useHeight;  spn_h.enabled=ui.useHeight;  spn_h.value=ui.height
		chk_ac.checked  = ui.useAcross;  spn_ac.enabled=ui.useAcross; spn_ac.value=ui.across
		chk_al.checked  = ui.useAlign;   rdo_al.enabled=ui.useAlign
		if ui.align!=undefined do
			try(rdo_al.state=case (ui.align as string) of ("left":1;"center":2;"right":3;default:1)) catch()
		chk_off.checked = ui.useOffset
		spn_ox.enabled=spn_oy.enabled=ui.useOffset
		spn_ox.value=ui.offset[1]; spn_oy.value=ui.offset[2]
		chk_pos.checked = ui.usePos
		spn_px.enabled=spn_py.enabled=ui.usePos
		spn_px.value=ui.pos[1]; spn_py.value=ui.pos[2]
		edt_tip.text=ui.tooltip
		edt_cmt.text=ui.comment
	)

	on RL_CommonParams open do load()

	on edt_n entered text do (
		local filtered=""
		for tok in filterString text " :()[],./\\?!\"'" do append filtered tok
		edt_n.text=filtered
		if filtered!=newRollout.controls[newRollout.activeControl].controlName do
		(
			if (for o in newRollout.controls where o.controlName==filtered collect o).count==0 then (
				newRollout.controls[newRollout.activeControl].controlName=filtered
				try(RL_Controls.refreshList()) catch()
				refreshPreview()
			) else (
				messageBox "Name already in use." title:"GUI Editor" beep:false
				edt_n.text=newRollout.controls[newRollout.activeControl].controlName
			)
		)
	)
	on edt_l  entered text do ( newRollout.controls[newRollout.activeControl].label=text; try(RL_Controls.refreshList())catch(); refreshPreview() )
	on chk_en changed s do  ( newRollout.controls[newRollout.activeControl].enabled=s; refreshPreview() )
	on chk_vis changed s do ( newRollout.controls[newRollout.activeControl].useVisible=s; refreshPreview() )
	on chk_w  changed s do  ( newRollout.controls[newRollout.activeControl].useWidth=spn_w.enabled=s; refreshPreview() )
	on spn_w  changed v do  ( newRollout.controls[newRollout.activeControl].width=v; refreshPreview() )
	on btn_fw pressed do (
		local w=newRollout.rolloutWidth-10
		chk_w.checked=spn_w.enabled=newRollout.controls[newRollout.activeControl].useWidth=true
		spn_w.value=newRollout.controls[newRollout.activeControl].width=w; refreshPreview()
	)
	on chk_pct changed s do ( newRollout.controls[newRollout.activeControl].usePercentageWidth=spn_pct.enabled=s; refreshPreview() )
	on spn_pct changed v do ( newRollout.controls[newRollout.activeControl].percentageWidth=v; refreshPreview() )
	on chk_h  changed s do  ( newRollout.controls[newRollout.activeControl].useHeight=spn_h.enabled=s; refreshPreview() )
	on spn_h  changed v do  ( newRollout.controls[newRollout.activeControl].height=v; refreshPreview() )
	on chk_ac changed s do  ( newRollout.controls[newRollout.activeControl].useAcross=spn_ac.enabled=s; refreshPreview() )
	on spn_ac changed v do  ( newRollout.controls[newRollout.activeControl].across=v; refreshPreview() )
	on chk_al changed s do  ( newRollout.controls[newRollout.activeControl].useAlign=rdo_al.enabled=s; refreshPreview() )
	on rdo_al changed s do  ( newRollout.controls[newRollout.activeControl].align=case s of(1:#left;2:#center;3:#right;default:#left); refreshPreview() )
	on chk_off changed s do ( newRollout.controls[newRollout.activeControl].useOffset=spn_ox.enabled=spn_oy.enabled=s; refreshPreview() )
	on spn_ox changed v do  ( newRollout.controls[newRollout.activeControl].offset[1]=v; refreshPreview() )
	on spn_oy changed v do  ( newRollout.controls[newRollout.activeControl].offset[2]=v; refreshPreview() )
	on chk_pos changed s do ( newRollout.controls[newRollout.activeControl].usePos=spn_px.enabled=spn_py.enabled=s; refreshPreview() )
	on spn_px changed v do  ( newRollout.controls[newRollout.activeControl].pos[1]=v; refreshPreview() )
	on spn_py changed v do  ( newRollout.controls[newRollout.activeControl].pos[2]=v; refreshPreview() )
	on edt_tip entered text do ( newRollout.controls[newRollout.activeControl].tooltip=text; refreshPreview() )
	on edt_cmt entered text do ( newRollout.controls[newRollout.activeControl].comment=text )
)

-- ==============================================================
-- SECTION 12: ROLLOUT PROPERTIES PANEL
-- ==============================================================

rollout RL_RolloutParams "Rollout Properties" (
	label lbl_n "Name:"  across:2 align:#left offset:[0,3]
	edittext edt_n "" fieldWidth:162
	label lbl_t "Title:" across:2 align:#left offset:[0,3]
	edittext edt_t "" fieldWidth:162
	label lbl_w "Width:"  across:2 align:#left offset:[0,3]
	spinner spn_w "" type:#integer range:[100,4000,330] fieldWidth:60
	checkbox chk_h "Fixed Height" across:2
	spinner  spn_h "" type:#integer range:[100,4000,500] fieldWidth:60 enabled:false
	group "Colors" (
		colorpicker cpl_bg "Background" align:#right
		colorpicker cpl_fg "Foreground" align:#right
	)
	group "Window Style" (
		multilistBox mlbx_st "" height:4 items:#("style_titlebar","style_border","style_toolwindow","style_resizing","style_minimizebox","style_maximizebox","style_sysmenu","style_sunkenedge")
	)
	checkbox chk_lw "Lock Width"     across:2
	checkbox chk_lh "Lock Height"
	checkbox chk_esc "Enable Escape" across:2
	checkbox chk_md  "Modal"

	fn load = (
		edt_n.text=newRollout.rolloutName; edt_t.text=newRollout.rolloutTitle
		spn_w.value=newRollout.rolloutWidth
		chk_h.checked=newRollout.useHeight; spn_h.value=newRollout.rolloutHeight; spn_h.enabled=newRollout.useHeight
		if newRollout.bgcolor!=undefined do cpl_bg.color=newRollout.bgcolor
		if newRollout.fgcolor!=undefined do cpl_fg.color=newRollout.fgcolor
		local allSt=#("style_titlebar","style_border","style_toolwindow","style_resizing","style_minimizebox","style_maximizebox","style_sysmenu","style_sunkenedge")
		local sel=#{}
		if newRollout.style!=undefined do
			for i=1 to allSt.count do
				for s in newRollout.style do
					if (s as string)==allSt[i] do sel[i]=true
		try(mlbx_st.selection=sel) catch()
		chk_lw.checked=newRollout.lockWidth; chk_lh.checked=newRollout.lockHeight
		chk_esc.checked=newRollout.doEscapeEnable; chk_md.checked=newRollout.modal
	)
	on RL_RolloutParams open do load()
	on edt_n  entered text do ( newRollout.rolloutName=text; refreshPreview() )
	on edt_t  entered text do ( newRollout.rolloutTitle=text; refreshPreview() )
	on spn_w  changed v do   ( newRollout.rolloutWidth=v; refreshPreview() )
	on chk_h  changed s do   ( newRollout.useHeight=spn_h.enabled=s; refreshPreview() )
	on spn_h  changed v do   ( newRollout.rolloutHeight=v; refreshPreview() )
	on cpl_bg changed col do ( newRollout.bgcolor=col; refreshPreview() )
	on cpl_fg changed col do ( newRollout.fgcolor=col; refreshPreview() )
	on mlbx_st selected sel do (
		local allSt=#(#style_titlebar,#style_border,#style_toolwindow,#style_resizing,#style_minimizebox,#style_maximizebox,#style_sysmenu,#style_sunkenedge)
		newRollout.style=for i in mlbx_st.selection collect allSt[i]
		refreshPreview()
	)
	on chk_lw  changed s do ( newRollout.lockWidth=s )
	on chk_lh  changed s do ( newRollout.lockHeight=s )
	on chk_esc changed s do ( newRollout.doEscapeEnable=s )
	on chk_md  changed s do ( newRollout.modal=s )
)

-- ==============================================================
-- SECTION 13: EVENT HANDLER EDITOR
-- ==============================================================

rollout RL_EventHandlers "Event Handlers" (
	dropdownlist ddl_ctrl  "Control:"  align:#right
	dropdownlist ddl_event "Event:"    align:#right
	edittext edt_args "Args (e.g. val):" labelOnTop:true
	edittext edt_code "Code:" labelOnTop:true height:65
	button btn_apply  "Apply / Add Handler" across:2 width:170
	button btn_rem    "Remove Handler"       width:170

	fn refreshCtrlList = (
		ddl_ctrl.items = for o in newRollout.controls where (getValidEvents o.controlType).count>0 collect
			(o.controlName + "  (" + o.controlType + ")")
		if newRollout.activeControl>0 and newRollout.activeControl<=newRollout.controls.count do
		(
			local ui=newRollout.controls[newRollout.activeControl]
			local idx=findItem ddl_ctrl.items (ui.controlName + "  (" + ui.controlType + ")")
			if idx>0 do ddl_ctrl.selection=idx
		)
	)
	fn loadHandlerCode = (
		if ddl_ctrl.selection==0 or ddl_event.selection==0 do return undefined
		local validCtrls=for o in newRollout.controls where (getValidEvents o.controlType).count>0 collect o
		if ddl_ctrl.selection>validCtrls.count do return undefined
		local ui=validCtrls[ddl_ctrl.selection]
		local evName=ddl_event.items[ddl_event.selection]
		local existing=for eh in ui.eventHandlers where eh.event==evName collect eh
		if existing.count>0 then ( edt_args.text=existing[1].args; edt_code.text=existing[1].code )
		else ( edt_args.text=""; edt_code.text="\t\t-- code here\n" )
	)
	on RL_EventHandlers open do (
		refreshCtrlList()
		if ddl_ctrl.selection>0 do (
			local validCtrls=for o in newRollout.controls where (getValidEvents o.controlType).count>0 collect o
			if ddl_ctrl.selection<=validCtrls.count do
			(
				ddl_event.items=getValidEvents validCtrls[ddl_ctrl.selection].controlType
				if ddl_event.items.count>0 do ( ddl_event.selection=1; loadHandlerCode() )
			)
		)
	)
	on ddl_ctrl selected sel do (
		local validCtrls=for o in newRollout.controls where (getValidEvents o.controlType).count>0 collect o
		if sel<=validCtrls.count do (
			ddl_event.items=getValidEvents validCtrls[sel].controlType
			if ddl_event.items.count>0 do ( ddl_event.selection=1; loadHandlerCode() )
		)
	)
	on ddl_event selected sel do loadHandlerCode()
	on btn_apply pressed do (
		if ddl_ctrl.selection>0 and ddl_event.selection>0 do
		(
			local validCtrls=for o in newRollout.controls where (getValidEvents o.controlType).count>0 collect o
			if ddl_ctrl.selection<=validCtrls.count do
			(
				local ui=validCtrls[ddl_ctrl.selection]
				local evName=ddl_event.items[ddl_event.selection]
				for i=ui.eventHandlers.count to 1 by -1 where ui.eventHandlers[i].event==evName do
					deleteItem ui.eventHandlers i
				append ui.eventHandlers (eventHandlerStruct event:evName args:edt_args.text code:edt_code.text)
			)
		)
	)
	on btn_rem pressed do (
		if ddl_ctrl.selection>0 and ddl_event.selection>0 do
		(
			pushUndo()
			local validCtrls=for o in newRollout.controls where (getValidEvents o.controlType).count>0 collect o
			if ddl_ctrl.selection<=validCtrls.count do
			(
				local ui=validCtrls[ddl_ctrl.selection]
				local evName=ddl_event.items[ddl_event.selection]
				for i=ui.eventHandlers.count to 1 by -1 where ui.eventHandlers[i].event==evName do
					deleteItem ui.eventHandlers i
			)
		)
	)
)

-- ==============================================================
-- SECTION 14: MACROSCRIPT SETTINGS PANEL
-- ==============================================================

rollout RL_MacroConfig "MacroScript Settings" (
	label lbl_ "Configure the generated MacroScript:" align:#center
	label lbl_n "Script Name:"   across:2 align:#left offset:[0,3]
	edittext edt_n  "" fieldWidth:162
	label lbl_c "Category:"      across:2 align:#left offset:[0,3]
	edittext edt_c  "" fieldWidth:162
	label lbl_i "Internal Name:" across:2 align:#left offset:[0,3]
	edittext edt_i  "" fieldWidth:162
	label lbl_tt "Tooltip:"      across:2 align:#left offset:[0,3]
	edittext edt_tt "" fieldWidth:162
	label lbl_bt "Button Text:"  across:2 align:#left offset:[0,3]
	edittext edt_bt "" fieldWidth:162
	on RL_MacroConfig open do (
		edt_n.text=macroScriptConfig.scriptName; edt_c.text=macroScriptConfig.category
		edt_i.text=macroScriptConfig.internalName; edt_tt.text=macroScriptConfig.toolTip
		edt_bt.text=macroScriptConfig.buttonText
	)
	on edt_n  entered text do ( macroScriptConfig.scriptName=text )
	on edt_c  entered text do ( macroScriptConfig.category=text )
	on edt_i  entered text do ( macroScriptConfig.internalName=text )
	on edt_tt entered text do ( macroScriptConfig.toolTip=text )
	on edt_bt entered text do ( macroScriptConfig.buttonText=text )
)

-- ==============================================================
-- SECTION 15: CONTROLS LIST (Left Panel)
-- ==============================================================

rollout RL_Controls "Controls" (
	listbox lbx_list "" height:17 items:#()
	button btn_up  "▲ Up"     across:4 width:83 tooltip:"Move up"
	button btn_dn  "▼ Down"   width:83           tooltip:"Move down"
	button btn_dup "⊕ Dup"    width:83           tooltip:"Duplicate"
	button btn_rem "✕ Remove" width:83           tooltip:"Remove"
	button btn_und "↩ Undo"   across:2 width:165 tooltip:"Undo"
	button btn_red "↪ Redo"   width:165           tooltip:"Redo"

	group "Add Control" (
		button b_lbl "Label"     across:4 width:83 height:22 tooltip:"Label"
		button b_edt "Edittext"           width:83 height:22 tooltip:"Edittext"
		button b_spn "Spinner"            width:83 height:22 tooltip:"Spinner"
		button b_sld "Slider"             width:83 height:22 tooltip:"Slider"

		button b_btn "Button"    across:4 width:83 height:22 tooltip:"Button"
		button b_chk "Checkbox"           width:83 height:22 tooltip:"Checkbox"
		button b_cbt "ChkButton"          width:83 height:22 tooltip:"CheckButton"
		button b_pbt "PickButton"         width:83 height:22 tooltip:"PickButton"

		button b_ddl "Dropdown"  across:4 width:83 height:22 tooltip:"DropdownList"
		button b_lbx "Listbox"            width:83 height:22 tooltip:"Listbox"
		button b_mlb "MultiList"          width:83 height:22 tooltip:"MultiListbox"
		button b_cbo "Combobox"           width:83 height:22 tooltip:"Combobox"

		button b_cpl "Color"     across:4 width:83 height:22 tooltip:"ColorPicker"
		button b_rdo "Radio"              width:83 height:22 tooltip:"Radiobuttons"
		button b_ang "Angle"              width:83 height:22 tooltip:"Angle"
		button b_prg "Progress"           width:83 height:22 tooltip:"ProgressBar"

		button b_hyp "Hyperlink" across:4 width:83 height:22 tooltip:"Hyperlink"
		button b_bmp "Bitmap"             width:83 height:22 tooltip:"Bitmap"
		button b_img "ImgTag"             width:83 height:22 tooltip:"ImgTag"
		button b_cc  "Curve"              width:83 height:22 tooltip:"CurveControl"

		button b_gbx "GroupBox"  across:4 width:83 height:22 tooltip:"GroupBox"
		button b_grp "Group ()"           width:83 height:22 tooltip:"Group block"
		button b_sub "SubRollout"         width:83 height:22 tooltip:"SubRollout"
		button b_tmr "Timer"              width:83 height:22 tooltip:"Timer"

		button b_mbt "MapBtn"    across:4 width:83 height:22 tooltip:"MapButton"
		button b_xbt "MatBtn"             width:83 height:22 tooltip:"MaterialButton"
	)

	fn refreshList = (
		lbx_list.items=for o in newRollout.controls collect (o.controlType+"  "+o.controlName+"  \""+o.label+"\"")
		if newRollout.activeControl>0 and newRollout.activeControl<=lbx_list.items.count do
			lbx_list.selection=newRollout.activeControl
	)

	fn loadTypePanel = (
		if RL_GUIEditor==undefined do return undefined
		local sel=newRollout.activeControl
		local tp=RL_PropNone
		if sel>0 and sel<=newRollout.controls.count do
		(
			local ui=newRollout.controls[sel]
			tp=case ui.controlType of (
				"spinner":RL_PropSpinner; "checkbox":RL_PropCheckbox; "button":RL_PropButton
				"checkbutton":RL_PropCheckbutton; "pickbutton":RL_PropPickbutton
				"mapbutton":RL_PropMapButton; "materialbutton":RL_PropMapButton
				"edittext":RL_PropEdittext; "listbox":RL_PropListItems; "multilistbox":RL_PropListItems
				"combobox":RL_PropItems; "dropdownlist":RL_PropItems
				"radiobuttons":RL_PropRadiobuttons; "colorpicker":RL_PropColorpicker
				"slider":RL_PropSlider; "angle":RL_PropAngle; "hyperlink":RL_PropHyperlink
				"progressBar":RL_PropProgressbar; "timer":RL_PropTimer; "bitmap":RL_PropBitmap
				"imgTag":RL_PropImgTag; "label":RL_PropLabel; "curveControl":RL_PropCurveControl
				default:RL_PropNone
			)
		)
		if RL_GUIEditor.sub_right.rollouts.count>=2 do
			try(removeSubRollout RL_GUIEditor.sub_right RL_GUIEditor.sub_right.rollouts[2]) catch()
		addSubRollout RL_GUIEditor.sub_right tp
	)

	on RL_Controls open do refreshList()

	on lbx_list selected sel do (
		newRollout.activeControl=sel
		RL_CommonParams.load()
		loadTypePanel()
		try(RL_EventHandlers.refreshCtrlList()) catch()
	)

	fn doAdd type = (
		addControlToRollout type
		refreshList()
		RL_CommonParams.load()
		loadTypePanel()
		refreshPreview()
	)

	on b_lbl pressed do doAdd "label"
	on b_edt pressed do doAdd "edittext"
	on b_spn pressed do doAdd "spinner"
	on b_sld pressed do doAdd "slider"
	on b_btn pressed do doAdd "button"
	on b_chk pressed do doAdd "checkbox"
	on b_cbt pressed do doAdd "checkbutton"
	on b_pbt pressed do doAdd "pickbutton"
	on b_ddl pressed do doAdd "dropdownlist"
	on b_lbx pressed do doAdd "listbox"
	on b_mlb pressed do doAdd "multilistbox"
	on b_cbo pressed do doAdd "combobox"
	on b_cpl pressed do doAdd "colorpicker"
	on b_rdo pressed do doAdd "radiobuttons"
	on b_ang pressed do doAdd "angle"
	on b_prg pressed do doAdd "progressBar"
	on b_hyp pressed do doAdd "hyperlink"
	on b_bmp pressed do doAdd "bitmap"
	on b_img pressed do doAdd "imgTag"
	on b_cc  pressed do doAdd "curveControl"
	on b_gbx pressed do doAdd "groupbox"
	on b_grp pressed do (
		addControlToRollout "groupstart"; addControlToRollout "groupend"
		refreshList(); refreshPreview()
	)
	on b_sub pressed do doAdd "subRollout"
	on b_tmr pressed do doAdd "timer"
	on b_mbt pressed do doAdd "mapbutton"
	on b_xbt pressed do doAdd "materialbutton"

	on btn_up pressed do (
		local sel=newRollout.activeControl
		if sel>1 do (
			pushUndo(); swap newRollout.controls[sel] newRollout.controls[sel-1]
			newRollout.activeControl=sel-1; refreshList(); refreshPreview()
		)
	)
	on btn_dn pressed do (
		local sel=newRollout.activeControl
		if sel>0 and sel<newRollout.controls.count do (
			pushUndo(); swap newRollout.controls[sel] newRollout.controls[sel+1]
			newRollout.activeControl=sel+1; refreshList(); refreshPreview()
		)
	)
	on btn_dup pressed do (
		local sel=newRollout.activeControl
		if sel>0 do (
			pushUndo()
			local dup=deepCopyControl newRollout.controls[sel]
			local base=dup.controlName; local n=2
			local existing=for o in newRollout.controls collect o.controlName
			while findItem existing dup.controlName!=0 do ( dup.controlName=base+"_"+n as string; n+=1 )
			insertItem dup newRollout.controls (sel+1)
			newRollout.activeControl=sel+1
			refreshList(); RL_CommonParams.load(); loadTypePanel(); refreshPreview()
		)
	)
	on btn_rem pressed do (
		local sel=newRollout.activeControl
		if sel>0 do (
			pushUndo()
			if newRollout.controls[sel].controlType=="groupstart" do
			(
				local gn=newRollout.controls[sel].controlName
				for i=newRollout.controls.count to 1 by -1 where
					newRollout.controls[i].controlType=="groupend" and
					newRollout.controls[i].controlName==gn do
					deleteItem newRollout.controls i
			)
			deleteItem newRollout.controls sel
			newRollout.activeControl=if newRollout.controls.count>0 then (min sel newRollout.controls.count) else 0
			refreshList()
			if newRollout.activeControl>0 then ( RL_CommonParams.load(); loadTypePanel() )
			else loadTypePanel()
			refreshPreview()
		)
	)
	on btn_und pressed do (
		doUndo(); refreshList()
		try(RL_RolloutParams.load())catch()
		if newRollout.activeControl>0 do RL_CommonParams.load()
		loadTypePanel(); try(RL_EventHandlers.refreshCtrlList())catch()
		refreshPreview()
	)
	on btn_red pressed do (
		doRedo(); refreshList()
		try(RL_RolloutParams.load())catch()
		if newRollout.activeControl>0 do RL_CommonParams.load()
		loadTypePanel(); try(RL_EventHandlers.refreshCtrlList())catch()
		refreshPreview()
	)
)

-- ==============================================================
-- SECTION 16: SAVE / LOAD / CODE OUTPUT
-- ==============================================================

rollout RL_SaveLoad "Save / Load / Code" (
	button btn_save   "Save Layout..."     across:2 width:165
	button btn_load   "Load Layout..."     width:165
	button btn_import "Import .ms File..." across:2 width:165
	button btn_new    "New / Reset"        width:165
	separator sep_ "" offset:[0,2]
	radiobuttons rdo_mode "" labels:#("Rollout","Full MacroScript") columns:2 state:2 align:#left
	button btn_build "Generate Code"       width:338 align:#right
	button btn_exec  "Execute Code" across:2 width:165
	button btn_copy  "Copy to Clipboard"   width:165
	edittext edt_code "" height:140 readOnly:true

	on btn_save pressed do (
		local f=getSaveFileName caption:"Save Layout" types:"GUI Layout (*.dat)|*.dat|All|*.*|"
		if f!=undefined do (
			with printAllElements on (
				local fh=createFile f
				format "%" (newRollout as string) to:fh
				close fh
			)
			messageBox "Saved." title:"GUI Editor" beep:false
		)
	)
	on btn_load pressed do (
		local f=getOpenFileName caption:"Load Layout" types:"GUI Layout (*.dat)|*.dat|All|*.*|"
		if f!=undefined do (
			local fh=openFile f
			newRollout=readValue fh
			close fh
			local fresh=rolloutConstructor()
			for p in getpropnames fresh do
				if (getproperty newRollout p)==undefined do
					try(setproperty newRollout p (getproperty fresh p))catch()
			for ctrl in newRollout.controls do (
				local fc=UIControlStruct()
				for p in getpropnames fc do
					if (getproperty ctrl p)==undefined do
						try(setproperty ctrl p (getproperty fc p))catch()
			)
			try(RL_Controls.refreshList())catch()
			try(RL_RolloutParams.load())catch()
			try(RL_EventHandlers.refreshCtrlList())catch()
			refreshPreview()
		)
	)
	on btn_import pressed do (
		local f=getOpenFileName caption:"Import MAXScript" types:"MAXScript (*.ms)|*.ms|All|*.*|"
		if f!=undefined do (
			local fh=openFile f; local code=""
			while not eof fh do append code (readLine fh+"\n")
			close fh
			local parsed=parseMAXScriptCode code
			if parsed.controls.count>0 then (
				pushUndo(); newRollout=parsed
				try(RL_Controls.refreshList())catch()
				try(RL_RolloutParams.load())catch()
				refreshPreview()
				messageBox ("Imported "+parsed.controls.count as string+" controls.") title:"GUI Editor" beep:false
			) else
				messageBox "No controls found." title:"GUI Editor"
		)
	)
	on btn_new pressed do (
		if queryBox "Reset all controls?" title:"GUI Editor" do (
			pushUndo(); newRollout=rolloutConstructor()
			try(RL_Controls.refreshList())catch()
			try(RL_RolloutParams.load())catch()
			refreshPreview()
		)
	)
	on btn_build pressed do (
		edt_code.text = if rdo_mode.state==1 then (buildRolloutCode buildUICode:true) else buildMacroScriptCode()
	)
	on btn_exec pressed do (
		local code=if rdo_mode.state==1 then (buildRolloutCode buildUICode:true) else buildMacroScriptCode()
		try(execute code)catch(e)(messageBox ("Error:\n"+e as string) title:"Execute Error")
	)
	on btn_copy pressed do (
		local code=if rdo_mode.state==1 then (buildRolloutCode buildUICode:true) else buildMacroScriptCode()
		edt_code.text=code
		try(
			local dataObj=dotNetObject "System.Windows.Forms.DataObject"
			dataObj.SetData "Text" code
			(dotNetClass "System.Windows.Forms.Clipboard").SetDataObject dataObj true
			messageBox "Copied to clipboard." title:"GUI Editor" beep:false
		)catch(
			messageBox "Clipboard copy failed." title:"GUI Editor"
		)
	)
)

-- ==============================================================
-- SECTION 17: MAIN DIALOG
-- ==============================================================

rollout RL_GUIEditor ("MAXScript GUI Editor  v" + TOOLS_VERSION) width:750 (
	subRollout sub_left  "" across:2 width:358 height:720 align:#left
	subRollout sub_right ""          width:368 height:720 align:#right

	on RL_GUIEditor open do (
		addSubRollout sub_left RL_Controls
		addSubRollout sub_left RL_RolloutParams  rolledUp:true
		addSubRollout sub_left RL_MacroConfig    rolledUp:true
		addSubRollout sub_left RL_EventHandlers  rolledUp:true
		addSubRollout sub_left RL_SaveLoad       rolledUp:true

		addSubRollout sub_right RL_CommonParams
		addSubRollout sub_right RL_PropNone

		RL_Controls.refreshList()
		if newRollout.activeControl>0 do ( RL_CommonParams.load(); RL_Controls.loadTypePanel() )
		pushUndo()
		refreshPreview()
	)
	on RL_GUIEditor close do (
		try(destroyDialog RL_Preview) catch()
		GUI_EditorPos=getDialogPos RL_GUIEditor
	)
	on RL_GUIEditor resized val do (
		sub_left.height=val[2]-10; sub_right.height=val[2]-10
	)
)

-- ==============================================================
-- SECTION 18: MACROSCRIPT ENTRY POINT
-- ==============================================================

macroScript MAXScript_GUI_Editor
	category:"Tools"
	internalName:"MAXScript_GUI_Editor"
	toolTip:"MAXScript GUI Editor — Visual Rollout Designer"
	buttonText:"GUI Editor"
(
	try(destroyDialog RL_GUIEditor) catch()
	try(destroyDialog RL_Preview)   catch()

	createDialog RL_GUIEditor
		style:#(#style_titlebar, #style_border, #style_sysmenu, #style_minimizebox, #style_resizing)
		lockWidth:false

	if GUI_EditorPos!=undefined do setDialogPos RL_GUIEditor GUI_EditorPos
)
