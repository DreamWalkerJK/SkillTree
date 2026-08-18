# <center>Nginx</center>  

### 1、proxy_pass 反向代理  

proxy_pass 用于将请求代理到后端服务器，配置时的 URL 末尾斜杠 ```/``` 的写法会影响转发路径。  

#### 绝对根路径 vs 相对路径  

- 绝对根路径：在 proxy_pass 后面的 URL 以斜杠 / 结束，表示绝对根路径。

```
location /proxy/ {
    proxy_pass http://127.0.0.1/;
}
```
例如，访问 http://example.com/proxy/test.html 会被转发到 http://127.0.0.1/test.html。

- 相对路径：在 proxy_pass 后面的 URL 不以斜杠 / 结束，表示相对路径。

```
location /proxy/ {
    proxy_pass http://127.0.0.1;
}
```
例如，访问 http://example.com/proxy/test.html 会被转发到 http://127.0.0.1/proxy/test.html。

### 参考资料  
https://www.cnblogs.com/paul8339/p/18853076  