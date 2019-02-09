require 'sinatra/base'
require 'faye/websocket'
require 'json'
require 'socket'
require 'openssl'
require 'yaml'

RATE_LIMIT = 1024 # bytes per second, set to 0 to turn off

class Main < Sinatra::Base
#     use Rack::Auth::Basic, "Protected Area" do |username, password|
#       username == 'foo' && password == 'bar'
#     end

    @@clients = {}
    
    get '/ws' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)
            
            ws.on(:open) do |event|
                ws.send({:hello => 'world', :rate_limit => RATE_LIMIT}.to_json)
            end

            ws.on(:close) do |event|
            end

            ws.on(:message) do |msg|
#                 STDERR.puts request.to_yaml
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                begin
                    request = {}
                    unless msg.data.empty?
                        request = JSON.parse(msg.data)
                        STDERR.puts request.to_json
                    end
                    if request['action'] == 'open'
                        begin
                            @@clients[client_id] = TCPSocket.new(request['host'], request['port'])
                            @@clients[client_id].set_encoding('UTF-8')
                            if request['tls']
                                ssl_context = OpenSSL::SSL::SSLContext.new()
#                                 ssl_context.ssl_version = :SSLv23
                                @@clients[client_id] = OpenSSL::SSL::SSLSocket.new(@@clients[client_id], ssl_context)
                                @@clients[client_id].sync_close = true
                                @@clients[client_id].connect
                                @@clients[client_id].io.set_encoding('UTF-8')
                            end
                        rescue StandardError => e
                            @@clients.delete(client_id)
                            ws.send({:connection_error => e.to_s, :host => request['host'], :port => request['port'], :tls => request['tls']}.to_json)
                        end
                        if @@clients[client_id]
                            ws.send({:connected => true, :host => request['host'], :port => request['port'], :tls => request['tls'], :address => @@clients[client_id].peeraddr[3]}.to_json)
                            STDERR.puts @@clients[client_id].inspect
                            Thread.new do 
                                while true do
                                    break if @@clients[client_id].closed? || @@clients[client_id].eof?
                                    s = IO.select([@@clients[client_id]])
                                    t = Time.now.to_f
                                    bytes_read = 0
                                    while true do
                                        buffer = nil
                                        begin
                                            if RATE_LIMIT == 0
                                                buffer = @@clients[client_id].read_nonblock(4096)
                                            else
                                                while Time.now.to_f < t + bytes_read.to_f / RATE_LIMIT
                                                    sleep 0.1
                                                end
                                                buffer = @@clients[client_id].read_nonblock(RATE_LIMIT)
                                                bytes_read += buffer.size
                                            end
                                            buffer.force_encoding(Encoding::UTF_8)
                                            buffer.encode!(Encoding::UTF_16LE, invalid: :replace, replace: "\uFFFD")
                                            buffer.encode!(Encoding::UTF_8)
                                        rescue StandardError => e
                                            STDERR.puts e
                                            break
                                        end
                                        if buffer
                                            STDERR.puts "Received #{buffer.size} bytes."
                                            ws.send({:message => buffer}.to_json)
                                        end
                                        break if @@clients[client_id].closed?
                                    end
                                    break if @@clients[client_id].closed?
                                end
                                STDERR.puts "socket closed"
                                ws.send({:connected => false}.to_json)
                            end
                        end
                    elsif request['action'] == 'send'
                        if @@clients[client_id]
                            msg = request['message'].strip + "\r\n"
                            if RATE_LIMIT == 0
                                @@clients[client_id].write(msg)
                            else
                                t = Time.now.to_f
                                bytes_sent = 0
                                while !msg.empty?
                                    while Time.now.to_f < t + bytes_sent.to_f / RATE_LIMIT
                                        sleep 0.1
                                    end
                                    chunk = msg.slice!(0, RATE_LIMIT)
                                    @@clients[client_id].write(chunk)
                                    bytes_sent += chunk.size
                                end
                            end
                        end
                    elsif request['action'] == 'close'
                        begin
                            @@clients[client_id].close
                        rescue
                        end
                        ws.send({:connected => false}.to_json)
                    end
                rescue StandardError => e
                    STDERR.puts e
                end
            end

            ws.rack_response
        end
    end
    
    post '/api' do
        {:hello => 'world', :clients => @@clients.keys}.to_json
    end
    
    get '/boo' do
        'BOOO1!!!!'
    end
    
    run! if app_file == $0
end
