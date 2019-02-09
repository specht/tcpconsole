var connected = null;
var ws = null;
var input = null;
var message_queue = [];
window.interval = null;
window.message_to_append = null;
window.message_to_append_index = 0;
window.message_to_append_timestamp = 0.0;

function teletype() {
    var messages = $('#messages');
    var div = messages.children().last();
    var t = Date.now() / 1000.0;
    while ((window.message_to_append_index < window.message_to_append.length) && window.message_to_append_index < (t - window.message_to_append_timestamp) * window.rate_limit)
    {
        var c = document.createTextNode(window.message_to_append.charAt(window.message_to_append_index));
        div.append(c);
        window.message_to_append_index += 1;
    }
    if (window.message_to_append_index >= window.message_to_append.length)
    {
        clearInterval(window.interval);
        window.interval = null;
        window.message_to_append = null;
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 0);
}

function handle_message()
{
    console.log('handle_message');
    if (message_queue.length === 0 || window.interval !== null || window.message_to_append !== null)
        return;
    var message = message_queue[0];
    message_queue = message_queue.slice(1);
    which = message.which;
    msg = message.msg;
    timestamp = message.timestamp;
    var messages = $('#messages');
    var div = messages.children().last();
    if ((which === 'note') || (which === 'error') || (!div.hasClass(which)))
    {
        div = $('<div>').addClass('message ' + which);
        messages.append(div);
        $('<div>').addClass('timestamp').html(timestamp).appendTo(div);
        if (which === 'server' || which == 'client')
            $('<div>').addClass('tick').appendTo(div);
    }
    if (which === 'server' || which === 'client')
    {
        window.message_to_append = msg;
        if (which === 'client')
            window.message_to_append += "\n";
        window.message_to_append_timestamp = Date.now() / 1000.0;
        window.message_to_append_index = 0;
        var d = 1000 / window.rate_limit;
        if (d < 1)
            d = 1;
        console.log(d);
        window.interval = setInterval(teletype, d);
    }
    else
    {
        div.append(document.createTextNode(msg));
        div.append("<br />");
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 400);
}

function append(which, msg)
{
    var d = new Date();
    var timestamp = ('0' + d.getHours()).slice(-2) + ':' +
                    ('0' + d.getMinutes()).slice(-2) + ':' +
                    ('0' + d.getSeconds()).slice(-2);
    message_queue.push({which: which, timestamp: timestamp, msg: msg});
    if (message_queue.length === 1)
        setTimeout(handle_message, 0);
}

function append_client(msg)
{
    append('client', msg);
}

function append_server(msg)
{
    append('server', msg);
}

function append_note(msg)
{
    append('note', msg);
}

function append_error(msg)
{
    append('error', msg);
}

function keepAlive() { 
    var timeout = 20000;  
    if (ws.readyState == ws.OPEN) {  
        ws.send('');  
    }  
    timerId = setTimeout(keepAlive, timeout);  
}                  

function setup_ws(ws)
{
    ws.onopen = function () {
        keepAlive();
    }
    
    ws.onclose = function () {
    }
    
    ws.onmessage = function (msg) {
        data = JSON.parse(msg.data);
        console.log(data);
        if (data.hello === 'world')
        {
            window.rate_limit = data.rate_limit;
            $('#rate_limit').html('' + data.rate_limit);
        }
        else if (data.connected === true)
        {
            $('#connect').html('Disconnect');
            $('#host').prop('disabled', true);
            $('#port').prop('disabled', true);
            $('#tls').prop('disabled', true);
            $('#input').prop('disabled', false);
            $('#send').prop('disabled', false);
            connected = true;
            $('#input').val("");
            $('#input').focus();
            append_note('Connected to ' + data.host + ' ' + (data.tls ? '(TLS) ' : '') + '(' + data.address + ') on port ' + data.port + '.');
        }
        else if (data.connected === false)
        {
            $('#connect').html('Connect');
            $('#host').prop('disabled', false);
            $('#port').prop('disabled', false);
            $('#tls').prop('disabled', false);
            $('#input').prop('disabled', true);
            $('#send').prop('disabled', true);
            connected = false;
            append_note('Disconnected from host.');
        }
        else if (typeof(data.connection_error) !== 'undefined')
        {
            append_error('Failed connection attempt to ' + data.host + ' ' + (data.tls ? '(TLS) ' : '') + 'on port ' + data.port + ' (' + data.connection_error + ')');
        }
        else if (typeof(data.message) !== 'undefined')
        {
            append_server(data.message);
        }
        else if (typeof(data.note) !== 'undefined')
        {
            append_note(data.note);
        }
    }
}

function sendInput()
{
    var msg = input.val();
    append_client(msg);
    ws.send(JSON.stringify({action: 'send', message: msg}))
    input.val("");
}

$(document).ready(function() {
    connected = false;
    var ws_uri = 'ws://localhost:8020/ws';
    console.log(ws_uri);
    ws = new WebSocket(ws_uri);
    setup_ws(ws);
    input = $('#input')

    input.keydown(function (e) {
        if (e.originalEvent.keyCode == 13)
        {
            e.preventDefault();
            sendInput();
        }
    });

    $('#send').click(function(e) {
        sendInput();
        input.focus();
    });
    $('#clear').click(function(e) {
        $('#messages').empty();
    });
    $('#host').focus();
    $('#connect').click(function() {
        if (!connected)
            ws.send(JSON.stringify({
                action: 'open', 
                host: $('#host').val(), 
                port: parseInt($('#port').val()), 
                tls: $('#tls').prop('checked')
            }))
        else
            ws.send(JSON.stringify({
                action: 'close'
            }));
    });
});
