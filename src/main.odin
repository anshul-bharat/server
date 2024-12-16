package server

import "core:crypto/hash"
import "core:encoding/base64"
import "core:fmt"
import "core:log"
import "core:path/filepath"
import "core:strings"
import "websocket"

main :: proc() {
	context.logger = log.create_console_logger()

	server := websocket.Server{}

	websocket.init_server(&server)

	server.route_map = {
		"/ws" = proc(request: ^websocket.Request) -> ^websocket.Response {
			response := websocket.new_text_response()
			response.status = websocket.Status.SWITCHING_PROTOCOL
			// response.headers["Content-Type"] = websocket.CONTENT_TYPES[".html"]
			setup_response_headers(request, response)
			// response.body = "<h1> It Works! </h1>"
			return response
		},
	}

	websocket.serve(&server)
}


setup_response_headers :: proc(req: ^websocket.Request, res: ^websocket.Response) {
	// fmt.println("Web socket request")
	//258EAFA5-E914-47DA-95CA-C5AB0DC85B11
	websocket_key: string = strings.join(
		{req.headers["Sec-WebSocket-Key"], "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"},
		"",
	)
	// log.info(req.headers["Sec-WebSocket-Key"])
	sha1 := hash.hash_string(hash.Algorithm.Insecure_SHA1, websocket_key)
	base64_str, err := base64.encode(sha1)
	// log.info(base64_str)
	assert(err == nil, "cannot encode")

	res^.headers = map[string]string {
		"Connection"           = "Upgrade",
		"Upgrade"              = "websocket",
		"Sec-WebSocket-Accept" = base64_str,
	}
}

