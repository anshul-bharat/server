package http

import "core:bytes"
import "core:fmt"
import "core:log"
import "core:net"
import "core:os/os2"
import "core:path/filepath"
import "core:strings"

g_http_server: ^Server

Route_Proc :: proc(_: ^Request) -> ^Response
ResponseModifier_Proc :: proc(_: ^Request, __: ^Response)

Server :: struct {
	address:            net.Address,
	port:               int,
	socket:             net.TCP_Socket,
	views_dir:          string,
	public_dir:         string,
	route_map:          map[string]Route_Proc,
	response_modifiers: [dynamic]ResponseModifier_Proc,
}

Connection :: struct {
	client_socket: net.TCP_Socket,
	source:        net.Endpoint,
}

Request :: struct {
	connection: Connection,
	headers:    map[string]string, //HttpRequestHeaders,
	path:       string,
	method:     string,
	body:       string,
	raw:        string,
}

delete_request :: proc(request: ^Request) {
			for k, v in request.headers {
				delete(k)
				delete(v)
			}
			delete(request.headers)
			delete(request.method)
			delete(request.path)
}

RequestHeaders :: struct {
	host:                      string,
	connection:                string,
	pragma:                    string,
	cache_control:             string,
	sec_ch_ua:                 string,
	sec_ch_ua_mobile:          string,
	sec_ch_ua_platform:        string,
	dnt:                       string,
	upgrade_insecure_requests: string,
	user_agent:                string,
	accept:                    string,
	sec_fetch_site:            string,
	sec_fetch_mode:            string,
	sec_fetch_user:            string,
	sec_fetch_dest:            string,
	accept_encoding:           string,
	accept_language:           string,
	upgrade:                   string,
	sec_websocket_version:     string,
	sec_websocket_key:         string,
}

Response :: struct {
	status:  Status,
	headers: map[string]string,
	varient: union {
		^TextResponse,
		^BinaryResponse,
	},
}

TextResponse :: struct {
	using response: Response,
	body:           string,
}

new_text_response :: proc() -> ^TextResponse {
	response := new(TextResponse)
	response.status = .OK
	response.varient = response
	init_default_response_headers(response)

	return response
}

delete_text_response :: proc(response: ^TextResponse) {
	delete(response.headers)
	free(response)
}

BinaryResponse :: struct {
	using response: Response,
	body:           []byte,
}

new_binary_response :: proc() -> ^BinaryResponse {
	response := new(BinaryResponse)
	response.status = .OK
	response.varient = response
	init_default_response_headers(response)

	return response
}

delete_binary_response :: proc(response: ^BinaryResponse) {
	delete(response.headers)
	free(response)
}

delete_response :: proc(response: ^Response) {
	switch res in response.varient {
		case ^TextResponse:
			delete_text_response(res)
		case ^BinaryResponse:
			delete_binary_response(res)
	}
}

Status :: enum {
	OK        = 200,
	NOT_FOUND = 404,
}

FILE_TYPE_IDS :: enum {
	HTML,
	XML,
	TEXT,
	CSS,
	JS,
	BMP,
	JPG,
	JPEG,
	PNG,
	GIF,
	WEBP,
	SVG,
	JSON,
	BINARY
}

FILE_EXTENSTIONS := map[FILE_TYPE_IDS]string {
	.HTML   = "html",
	.XML   = "xml",
	.TEXT   = "txt",
	.CSS    = "css",
	.JS     = "js",
	.BMP    = "bmp",
	.JPG    = "jpg",
	.JPEG   = "jpeg",
	.PNG    = "png",
	.GIF    = "gif",
	.WEBP   = "webp",
	.SVG    = "svg",
	.JSON   = "json",
	.BINARY = "bin",
}

CONTENT_TYPES := map[FILE_TYPE_IDS]string {
	.HTML   = "text/html; charset=utf-8",
	.XML   = "text/xml; charset=utf-8",
	.TEXT   = "text/xml; charset=utf-8",
	.CSS    = "text/css; charset=utf-8",
	.JS     = "application/javascript; charset=utf-8",
	.BMP    = "image/bmp",
	.JPG    = "image/jpg",
	.JPEG   = "image/jpeg",
	.PNG    = "image/png",
	.GIF    = "image/gif",
	.WEBP   = "image/webp",
	.SVG    = "image/svg-xml",
	.JSON   = "application/json",
	.BINARY = "application/octet-stream",
}

get_filetype :: proc(filename: string) -> FILE_TYPE_IDS {
	ext, _ := strings.to_lower(filepath.ext(filename), context.temp_allocator)
	ext, _ = strings.replace_all(ext, ".", "", context.temp_allocator)
	for k,v in FILE_EXTENSTIONS {
		if v == ext {
			return k
		}
	}

	return .BINARY
}

file_exists :: proc(path: string) -> bool {
	server := g_http_server
	return os2.exists(filepath.join({server.public_dir, path}, context.temp_allocator)) \
		&& os2.is_file(filepath.join({server.public_dir, path}, context.temp_allocator))
}

init_server :: proc(server: ^Server) {
	g_http_server = server
}

delete_server :: proc(server: ^Server) {
	delete(server.views_dir)
	delete(server.public_dir)
	delete(server.response_modifiers)
	delete(server.route_map)
	free(server)
}

serve :: proc(server: ^Server, keep_running: proc() -> bool = nil) {
	if server.views_dir != "" && os2.exists(server.views_dir) == false {
		log.panic("Views directory does not exists: ", server.views_dir)
	}

	if server.public_dir != "" && os2.exists(server.public_dir) == false {
		log.panic("Views directory does not exists: ", server.views_dir)
	}

	endpoint, ok := net.parse_endpoint("127.0.0.1:8000")
	assert(ok, "cannot start server")
	server.port = endpoint.port
	server.address = endpoint.address

	socket, err := net.listen_tcp(endpoint)
	assert(err == nil, "cannot listen on socket")
	server.socket = socket

	log.info("Listening on port: ", server.port)

	for keep_running == nil || keep_running() {
		log.info("Waiting for connection")

		request := Request{}
		defer delete_request(&request)

		accept(server, &request)

		log.info("Route: ", request.path)

		if server.route_map[request.path] != nil {
			response := server.route_map[request.path](&request)
			defer delete_response(response)

			send(&request, response)
			
		} else if file_exists(request.path) {
			ext := get_filetype(request.path)
			log.info(ext)
			#partial switch (ext) {
			case .HTML, .XML, .CSS, .JS, .TEXT:
				{
					response := create_text_file_response(request.path)
					defer delete_response(response)
					
					send(&request, response)
				}
			case:
				{
					response := create_binary_response(request.path)
					defer delete_response(response)
				
					send(&request, response)
				}
			}
		} else {
			response := new_text_response()
			defer delete_response(response)
			
			response.status = .NOT_FOUND
			response.body = "<h1> Error: Resource not found </h1>"
			send(&request, response)
		}

		close(&request)
		free_all(context.temp_allocator)
	}
}

create_template_response :: proc(name: string) -> ^TextResponse {
	path := filepath.join({g_http_server.views_dir, name}, context.temp_allocator)

	response := new(TextResponse)
	response.status = .OK
	response.varient = response
	init_default_response_headers(response)
	response.headers["Content-Type"] = CONTENT_TYPES[.HTML]
	response.body = get_file_contents(path)

	return response
}

create_binary_response :: proc(name: string) -> ^BinaryResponse {
	path := filepath.join({g_http_server.public_dir, name}, context.temp_allocator)
	filetype := get_filetype(name)
	
	response := new_binary_response()
	response.headers["Content-Type"] = CONTENT_TYPES[filetype]
	response.body = get_file_bytes(path)

	return response
}

create_text_file_response :: proc(name: string) -> ^TextResponse {
	path := filepath.join({g_http_server.public_dir, name}, context.temp_allocator)
	filetype := get_filetype(name)
	
	response := new_text_response()
	response.headers["Content-Type"] = CONTENT_TYPES[filetype]
	response.body = get_file_contents(path)

	return response
}

init_default_response_headers :: proc(response: ^Response) {
	response.headers = {
		"Access-Control-Allow-Origin" = "*",
		"Connection"                  = "Keep-Alive",
		"Keep-Alive"                  = "timeout=5, max=997",
	}
}

modify_response :: proc(request: ^Request, response: ^Response) {
	for modifier in g_http_server.response_modifiers {
		modifier(request, response)
	}
}

accept :: proc(server: ^Server, request: ^Request) {
	client_socket, endpoint, err := net.accept_tcp(server.socket)
	assert(err == nil, "cannot create client socket")

	request.connection = Connection {
		client_socket = client_socket,
		source        = endpoint,
	}

	read(request)
}

read :: proc(request: ^Request) {
	bytes_recieved := [1024]u8{}
	bytes_buffer: bytes.Buffer
	defer bytes.buffer_destroy(&bytes_buffer)

	for {
		length, err := net.recv_tcp(request.connection.client_socket, bytes_recieved[:])
		// assert(err == nil, "cannot recieve from socket")
		if length == 0 || err != nil {
			break
		}

		bytes.buffer_write(&bytes_buffer, bytes_recieved[:length])
		break
	}

	request_bytes := bytes.buffer_to_bytes(&bytes_buffer)
	log.info("Recieved ", len(request_bytes), " bytes")

	if len(request_bytes) > 2 {
		request.raw = strings.string_from_ptr(&request_bytes[0], len(request_bytes))
	} else {
		request.raw = ""
	}

	parts := strings.split(request.raw, "\r\n\r\n", context.temp_allocator)
	assert(len(parts) > 0, "Request headers missing!")

	if len(parts) == 2 {
		request.body = parts[1]
	}

	header_parts := strings.split(parts[0], "\n", context.temp_allocator)
	line_1 := strings.split(header_parts[0], " ", context.temp_allocator)
	if len(line_1) < 2 {
		log.error("Invalid request")
	}
	request.path, _ = strings.clone(line_1[1])
	request.method, _ = strings.clone(line_1[0])

	for header_part, i in header_parts {
		if i == 0 {
			continue
		}

		key_value := strings.split(header_part, ": ", context.temp_allocator)
		for part, j in key_value {
			key_value[j] = strings.trim_space(part)
		}

		key, _ := strings.clone(key_value[0])
		value, _ := strings.clone(key_value[1])
		request.headers[key] = value
	}

}

send :: proc(request: ^Request, response: ^Response) {
	modify_response(request, response)

	response_buffer: bytes.Buffer
	defer bytes.buffer_destroy(&response_buffer)

	bytes.buffer_write_string(&response_buffer, "HTTP/1.1 ")
	switch response.status {
	case .OK:
		bytes.buffer_write_string(&response_buffer, "200 OK")
	case .NOT_FOUND:
		bytes.buffer_write_string(&response_buffer, "404 NOT FOUND")
	}
	bytes.buffer_write_string(&response_buffer, "\r\n")

	for key, value in response.headers {
		bytes.buffer_write_string(&response_buffer, key)
		bytes.buffer_write_string(&response_buffer, ": ")
		bytes.buffer_write_string(&response_buffer, value)
		bytes.buffer_write_string(&response_buffer, "\r\n")
	}

	bytes.buffer_write_string(&response_buffer, "\r\n")
	switch r in response.varient {
	case ^TextResponse:
		bytes.buffer_write_string(&response_buffer, r.body)
	case ^BinaryResponse:
		bytes.buffer_write(&response_buffer, r.body)
	}

	response_bytes := bytes.buffer_to_bytes(&response_buffer)
	bytes_sent := 0

	for bytes_sent < len(response_bytes) {
		n, send_error := net.send_tcp(request.connection.client_socket, response_bytes)
		if n == 0 || send_error != nil {
			break
		}

		bytes_sent += n
	}
	log.info("Sent ", len(response_bytes), " bytes")
}

close :: proc(request: ^Request) {
	net.shutdown(request.connection.client_socket, net.Shutdown_Manner.Both)
	net.close(request.connection.client_socket)
}

get_file_contents :: proc(path: string) -> string {
	return strings.clone_from_bytes(get_file_bytes(path), context.temp_allocator)
}

get_file_bytes :: proc(path: string) -> []byte {
	if os2.exists(path) == false {
		log.panic("File does not exists: ", path)
	}

	file_bytes, err := os2.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		log.panic("Cannot read file: ", err, "::", path)
	}

	return file_bytes
}
