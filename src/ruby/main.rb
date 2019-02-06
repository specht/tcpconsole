require 'sinatra/base'
require 'faye/websocket'
require 'json'
require 'socket'
require 'openssl'
require 'yaml'

class Main < Sinatra::Base
#     use Rack::Auth::Basic, "Protected Area" do |username, password|
#       username == 'foo' && password == 'bar'
#     end

    @@clients = {}
    
    get '/ws' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)
            
            ws.on(:open) do |event|
                puts 'On Open'
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                request = JSON.parse(msg.data)
                STDERR.puts request.to_json
                if request['action'] == 'open'
                    @@clients[client_id] = TCPSocket.new(request['host'], request['port'])
                    @@clients[client_id].set_encoding('UTF-8')
                    if request['tls']
                        ssl_context = OpenSSL::SSL::SSLContext.new()
                        ssl_context.ssl_version = :SSLv23
                        @@clients[client_id] = OpenSSL::SSL::SSLSocket.new(@@clients[client_id], ssl_context)
                        @@clients[client_id].sync_close = true
                        @@clients[client_id].connect
                        @@clients[client_id].io.set_encoding('UTF-8')
                    end
#                     ws.send('OPENED')
                    Thread.new do 
#                         while true do
#                             buffer = nil
#                             begin
#                                 buffer = @@clients[client_id].read_nonblock(1024)
#                             rescue EOFError
#                                 STDERR.puts "EOFError"
#                                 break
#                             rescue OpenSSL::SSL::SSLErrorWaitReadable
#                                 STDERR.puts "SSLErrorWaitReadable"
#                                 sleep(1)
#                             end
#                             if buffer
#                                 ws.send(buffer)
#                             end
#                             if @@clients[client_id].closed?
#                                 break
#                             end
#                         end
#                         STDERR.puts "socket closed"
                        while true do
                            break if @@clients[client_id].closed? || @@clients[client_id].eof?
                            STDERR.puts "select >"
                            s = IO.select([@@clients[client_id]])
                            STDERR.puts "<"
                            buffer = nil
                            begin
                                buffer = @@clients[client_id].read_nonblock(1024)
                                buffer.force_encoding('UTF-8')
                            rescue EOFError
                                STDERR.puts "EOFError"
                                break
                            rescue OpenSSL::SSL::SSLErrorWaitReadable
                                STDERR.puts "SSLErrorWaitReadable"
                                sleep(1)
                            end
                            if buffer
                                STDERR.puts "Received #{buffer.size} bytes."
                                ws.send(buffer)
                            end
                            if @@clients[client_id].closed?
                                break
                            end
                        end
                        STDERR.puts "socket closed"
                    end
                elsif request['action'] == 'send'
                    if @@clients[client_id]
                        @@clients[client_id].write(request['message'].strip)
                        @@clients[client_id].write("\r\n")
                    end
                elsif request['action'] == 'poll'
                    begin
                        buffer = @@clients[client_id].read_nonblock(1024)
                        ws.send(buffer)
                    rescue IO::EAGAINWaitReadable
                    rescue OpenSSL::SSL::SSLErrorWaitReadable
                    rescue EOFError
                        if @@clients[client_id]
                            @@clients.delete(client_id)
                        end
                        ws.send('CLOSE')
                    end
                end
            end

            ws.on(:close) do |event|
                puts 'On Close'
            end

            ws.rack_response
        end
    end
    
    post '/api' do
        {:hello => 'world'}.to_json
    end
    
    get '/boo' do
        'BOOO1!!!!'
    end
    
    run! if app_file == $0
end
