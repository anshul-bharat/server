package websocket

import "core:bytes"
import "core:fmt"
import "core:log"
import "core:net"
import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:time"

g_http_server: ^Server

Route_Proc :: proc(_: ^Request) -> ^Response
ResponseModifier_Proc :: proc(_: ^Request, __: ^Response)

Server :: struct {
	address:            net.Address,
	port:               int,
	socket:             net.TCP_Socket,
	route_map:          map[string]Route_Proc,
	response_modifiers: [dynamic]ResponseModifier_Proc,
}

Connection :: struct {
	client_socket: net.TCP_Socket,
	source:        net.Endpoint,
}

Request :: struct {
	connection: ^Connection,
	headers:    map[string]string, //HttpRequestHeaders,
	path:       string,
	method:     string,
	body:       string,
	raw:        string,
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

// HttpResponse :: union {
// 	HttpTextResponse,
// 	HttpBinaryResponse,
// }

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

Status :: enum {
	SWITCHING_PROTOCOL = 101,
	OK                 = 200,
	NOT_FOUND          = 404,
}

CONTENT_TYPES := map[string]string {
	".html" = "text/html; charset=utf-8",
	".css"  = "text/css; charset=utf-8",
	".js"   = "application/javascript; charset=utf-8",
	".bmp"  = "image/bmp",
	".jpg"  = "image/jpg",
	".jpeg" = "image/jpeg",
	".png"  = "image/png",
	".gif"  = "image/gif",
	".webp" = "image/webp",
	".svg"  = "image/svg-xml",
	".json" = "application/json",
	""      = "application/octet-stream",
}

init_server :: proc(server: ^Server) {
	g_http_server = server
}

new_request :: proc() -> ^Request {
	request := new(Request)
	request.connection = new(Connection)

	return request
}

free_request :: proc(req: ^Request) {
	free(req.connection)
	free(req)
}

serve :: proc(server: ^Server) {
	endpoint, ok := net.parse_endpoint("127.0.0.1:8000")
	assert(ok, "cannot start server")
	server.port = endpoint.port
	server.address = endpoint.address

	socket, err := net.listen_tcp(endpoint)
	assert(err == nil, "cannot listen on socket")
	server.socket = socket

	log.info("Listening on port: ", server.port)

	for {
		log.info("Waiting for connection")

		request := new_request()
		defer free_request(request)
		accept(server, request)

		log.info("Route: ", request.path)

		if server.route_map[request.path] != nil {
			response := server.route_map[request.path](request)
			switch r in response.varient {
			case ^TextResponse:
				send(request, r)
			case ^BinaryResponse:
				send(request, r)
			}
			handle_websocket(request.connection)
			free(response)
		} else {
			response := new_text_response()
			defer free(response)
			response.status = .NOT_FOUND
			response.body = "<h1> Error: Resource not found </h1>"
			send(request, response)
		}

		close(request)
	}
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
	client_socket, endpoint, err := net.accept_tcp(server.socket, {no_delay = false})
	assert(err == nil, "cannot create client socket")

	request.connection.client_socket = client_socket
	request.connection.source = endpoint

	read(request)
}

handle_websocket :: proc(connection: ^Connection) {

	// net.set_option(client_socket, net.Socket_Option.Reuse_Address, true)
	net.set_option(connection.client_socket, net.Socket_Option.Keep_Alive, true)
	net.set_option(connection.client_socket, net.Socket_Option.Send_Buffer_Size, 1024)
	net.set_option(connection.client_socket, net.Socket_Option.Receive_Buffer_Size, 1024)
	net.set_blocking(connection.client_socket, true)
	buf: [1024]byte
	// net.recv_tcp(connection.client_socket, buf[:])
	time.sleep(time.Second)
	for {
		// msg1 := []byte{129, 131, 61, 84, 35, 6, 112, 16, 109}
		// msg2 := []byte{0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f}
		// sent_bytes := net.send_tcp(connection.client_socket, msg1) or_break
		// log.info("SENT BYTES:", sent_bytes, size_of(msg3))

		nbytes := net.recv_tcp(connection.client_socket, buf[:]) or_break
		encoded_msg_bytes := buf[:nbytes]
		if len(encoded_msg_bytes) > 0 {
			decoded_msg_bytes := decode(encoded_msg_bytes[:])
			decoded_msg_str, err := strings.clone_from_bytes(decoded_msg_bytes)
			log.info("RECIEVED MSG: ", decoded_msg_str)
			// net.send_tcp(connection.client_socket, encoded_msg_bytes[:])
		}
		// break
		time.sleep(time.Second * 1)
	}
}

decode :: proc(str_bytes: []byte) -> []byte {

	if len(str_bytes) < 7 {
		return []byte{}
	}

	masked := false
	msg_length := 0

	if str_bytes[1] & 0b10000000 == 0b10000000 {
		masked = true
	}

	difference := str_bytes[1] - 128

	if difference >= 0 && difference <= 125 {
		msg_length = 5
	} else if difference == 126 {
		msg_length = 2
	} else if difference == 127 {
		msg_length = 8
	}

	mask := str_bytes[2:6]

	encoded_msg := str_bytes[6:]
	decoded_msg := encoded_msg

	for msg, i in encoded_msg {
		decoded_msg[i] = msg ~ mask[i % 4]
	}
	return decoded_msg
}
read :: proc(request: ^Request) {
	bytes_recieved := [1024]u8{}
	bytes_buffer: bytes.Buffer
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

	parts := strings.split(request.raw, "\r\n\r\n")
	assert(len(parts) > 0, "Request headers missing!")

	if len(parts) == 2 {
		request.body = parts[1]
	}

	header_parts := strings.split(parts[0], "\n")
	line_1 := strings.split(header_parts[0], " ")
	if len(line_1) < 2 {
		log.error("Invalid request")
	}
	request.path = line_1[1]
	request.method = line_1[0]

	for header_part, i in header_parts {
		if i == 0 {
			continue
		}

		key_value := strings.split(header_part, ": ")
		for part, j in key_value {
			key_value[j] = strings.trim_space(part)
		}

		request.headers[key_value[0]] = key_value[1]
	}
}

send :: proc(request: ^Request, response: ^Response) {
	modify_response(request, response)

	response_buffer: bytes.Buffer

	bytes.buffer_write_string(&response_buffer, "HTTP/1.1 ")
	switch response.status {
	case .SWITCHING_PROTOCOL:
		bytes.buffer_write_string(&response_buffer, "101 Switching Protocols")
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
	return strings.clone_from_bytes(get_file_bytes(path))
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

