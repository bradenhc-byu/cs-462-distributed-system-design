var http = require('http');
var url = require('url');
var fs = require('fs');

http.createServer(function (req, res) {
	var q = url.parse(req.url, true);
	var filename = (q.pathname.length > 1) ? "." + q.pathname : './index.html';
	fs.readFile(filename, function(err, data) {
		if (err) {
			res.writeHead(404, {'Content-Type': 'text/html'});
			return res.end("404 Not Found");
	    }
		res.writeHead(200, {'Content-Type': 'text/html',
							'Access-Control-Allow-Methods': 'GET, POST, PUT'});
		res.write(data);
		res.end();
	});
}).listen(8081);