class_name FSAServer
extends Node
## A tiny HTTP server on 127.0.0.1 (never the network) for agents:
##   GET  /health   -> {"ok": true, ...}
##   GET  /methods  -> the method list with what each takes
##   POST /rpc      {"method": "set_pose", "params": {...}}  ->  {"ok": true, "result": ...} | {"ok": false, "error": "..."}
## Calls run on the main thread between frames, through the same code as the UI (undo, live views, history).

const TIMEOUT_MS := 30000

var app: FSAApp
var api: FSAApi
var tcp := TCPServer.new()
var listening := false
var port := 0
var _clients: Array = []


func start(p: int) -> Error:
	api = FSAApi.new()
	api.app = app
	app.api = api
	var e := tcp.listen(p, "127.0.0.1")
	listening = e == OK
	port = p
	return e


func _exit_tree() -> void:
	tcp.stop()


func _process(_dt: float) -> void:
	if not listening:
		return
	while tcp.is_connection_available():
		_clients.append({"peer": tcp.take_connection(), "buf": PackedByteArray(), "t": Time.get_ticks_msec(), "busy": false})
	for c in _clients.duplicate():
		var cd: Dictionary = c
		if bool(cd["busy"]):
			continue
		var peer: StreamPeerTCP = cd["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(cd["t"]) > TIMEOUT_MS:
			_clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_data(n)
			if int(got[0]) == OK:
				var b: PackedByteArray = cd["buf"]   # packed arrays in a Dictionary are copies: write it back
				b.append_array(got[1])
				cd["buf"] = b
		var req := _parse(cd["buf"])
		if req.is_empty():
			continue
		cd["busy"] = true
		_serve(cd, req)


## {method, path, body} once the whole request is in, else {}
func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_ascii()
	var end := text.find("\r\n\r\n")
	if end < 0:
		return {}
	var head := text.substr(0, end)
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "body": ""}
	var length := 0
	for l in lines:
		if l.to_lower().begins_with("content-length:"):
			length = int(l.substr(15).strip_edges())
	if buf.size() < end + 4 + length:
		return {}
	var body := buf.slice(end + 4, end + 4 + length).get_string_from_utf8()
	return {"method": first[0], "path": first[1], "body": body}


func _serve(c: Dictionary, req: Dictionary) -> void:
	var out: Dictionary
	var path := str(req["path"]).split("?")[0]
	if req["method"] == "GET" and path == "/health":
		out = {"ok": true, "app": "fight-studio-animator", "version": FSAApp.VERSION, "fighter": app.fighter, "clip": app.doc.name}
	elif req["method"] == "GET" and path == "/methods":
		out = {"ok": true, "result": FSAApi.METHODS}
	elif req["method"] == "POST" and path == "/rpc":
		var parsed: Variant = JSON.parse_string(str(req["body"]))
		if typeof(parsed) != TYPE_DICTIONARY:
			out = {"ok": false, "error": "body must be JSON: {\"method\": ..., \"params\": {...}}"}
		else:
			out = await api.call_method(str((parsed as Dictionary).get("method", "")), (parsed as Dictionary).get("params", {}) if typeof((parsed as Dictionary).get("params", {})) == TYPE_DICTIONARY else {})
	else:
		out = {"ok": false, "error": "use POST /rpc, GET /methods or GET /health"}
	_send(c, out)


func _send(c: Dictionary, out: Dictionary) -> void:
	var peer: StreamPeerTCP = c["peer"]
	var body := JSON.stringify(out).to_utf8_buffer()
	var head := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(head.to_ascii_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()
	_clients.erase(c)
