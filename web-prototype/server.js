import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('.', import.meta.url)));
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'};
http.createServer(async (req,res)=>{try{const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);const safe=normalize(pathname).replace(/^([/\\]|[.][.][/\\])+/,'');const file=resolve(root,safe||'index.html');if(file!==root&&!file.startsWith(root+sep)){res.writeHead(403);res.end('Forbidden');return;}const data=await readFile(file);res.writeHead(200,{'content-type':types[extname(file)]||'application/octet-stream'});res.end(data)}catch{res.writeHead(404);res.end('Not found')}}).listen(4173,()=>console.log('ECHO POC running at http://localhost:4173'));
