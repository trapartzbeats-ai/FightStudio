class_name FSAImportDialog
extends RefCounted
## File > Import motion: pick a Mixamo FBX (or a GLB / glTF), then the few choices that matter, then it opens as a new clip.

const LAST_DIR_KEY := "import_dir"


static func open(app: FSAApp) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = "Import motion (Mixamo FBX, GLB, glTF)"
	fd.filters = PackedStringArray(["*.fbx ; Mixamo / FBX", "*.glb, *.gltf ; glTF"])
	var last := str(app.get_meta(LAST_DIR_KEY, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)))
	fd.current_dir = last
	fd.file_selected.connect(func(path: String) -> void:
		app.set_meta(LAST_DIR_KEY, path.get_base_dir())
		fd.queue_free()
		_options(app, path))
	fd.canceled.connect(func() -> void: fd.queue_free())
	app.add_child(fd)
	fd.popup_centered_ratio(0.6)


## the choices: name, in place, natural limits, fingers, and which animation when the file has more than one
static func _options(app: FSAApp, path: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Import %s" % path.get_file()
	dlg.ok_button_text = "Import"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var name_row := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "Clip name"
	nl.custom_minimum_size.x = 110
	var name_edit := LineEdit.new()
	name_edit.text = FSAMotionImport.suggest_name(path)
	name_edit.custom_minimum_size.x = 320
	name_row.add_child(nl)
	name_row.add_child(name_edit)
	box.add_child(name_row)
	var in_place := CheckBox.new()
	in_place.text = "In place (take the travel out; the game moves the fighter)"
	in_place.button_pressed = true
	var limits := CheckBox.new()
	limits.text = "Keep every joint inside the rig limits (knees never bend forward)"
	limits.button_pressed = true
	var fingers := CheckBox.new()
	fingers.text = "Bring the fingers too"
	fingers.button_pressed = true
	for cb in [in_place, limits, fingers]:
		box.add_child(cb)
	var hint := Label.new()
	hint.text = "Mixamo: download \"Without Skin\" (with skin works too), any frame rate.\nThe clip opens unsaved: look at it, then Save."
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	dlg.add_child(box)
	dlg.confirmed.connect(func() -> void:
		var opts := {"name": name_edit.text.strip_edges(), "in_place": in_place.button_pressed, "limits": limits.button_pressed,
			"fingers": fingers.button_pressed}
		dlg.queue_free()
		var go := func() -> void: app.import_motion(path, opts)
		if app.history.dirty():
			app.ask("\"%s\" has changes that are not saved. Import anyway (changes are lost)?" % app.doc.name, go)
		else:
			go.call())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	app.add_child(dlg)
	dlg.popup_centered()
	name_edit.grab_focus()
	name_edit.select_all()
