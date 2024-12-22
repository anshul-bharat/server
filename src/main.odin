package main

import "core:crypto/hash"
import "core:encoding/base64"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "websocket"
import "http"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
	
	main_http()
}

stop_server := false

main_http :: proc() {
	
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	
	server := new(http.Server)
	defer http.delete_server(server)
	
	server.public_dir = filepath.join({os.get_current_directory(context.temp_allocator), "/public"})
	server.views_dir = filepath.join({os.get_current_directory(context.temp_allocator), "/views"})
	server.response_modifiers = {}
	http.init_server(server)

	modifier: http.ResponseModifier_Proc = proc(request: ^http.Request, response: ^http.Response) {
		if response.headers["Content-Type"] == http.CONTENT_TYPES[http.FILE_TYPE_IDS.HTML] {
			if r := response.varient.(^http.TextResponse); r != nil {
				r.body = strings.join({r.body, "<h1>Hacked Response</h1>"}, "", context.temp_allocator)
			}
		}
	}
	append(&(server.response_modifiers), modifier)

	server.route_map = map[string]http.Route_Proc{}
	server.route_map["/"] = proc(request: ^http.Request) -> ^http.Response {
		return http.create_template_response("index.html")
	}
	server.route_map["/about"] = proc(request: ^http.Request) -> ^http.Response {
		return http.create_template_response("about.html")
	}
	server.route_map["/stop"] = proc(request: ^http.Request) -> ^http.Response {
		response := http.new_text_response()
		response.headers["Content-Type"] = http.CONTENT_TYPES[http.FILE_TYPE_IDS.JSON]
		response.body = "Shutting down server"
		stop_server = true
		return response
	}


	http.serve(server, proc() -> bool {return stop_server == false})
}

main_websocket :: proc() {
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

