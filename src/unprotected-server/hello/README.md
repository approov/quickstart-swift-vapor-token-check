# Unprotected Server Example

The unprotected example is the base reference to build the [Approov protected servers](/src/approov-protected-server/). This a very basic Hello World backend server in Swift, built with the Vapor framework.


## TOC - Table of Contents

* [Why?](#why)
* [How it Works?](#how-it-works)
* [Requirements](#requirements)
* [Try It](#try-it)


## Why?

To be the starting building block for the [Approov protected servers](/src/approov-protected-server/), that will show you how to lock down your API server to your mobile app. Please read the brief summary in the [README](/README.md#why) at the root of this repo or visit our [website](https://approov.io/product.html) for more details.

[TOC](#toc---table-of-contents)


## How it works?

The Swift server is very simple and is defined in this Vapor project [src/unprotected-server/hello](/src/unprotected-server/hello).

The server only replies to the endpoint `/` with the message:

```json
{"message": "Hello, World!"}
```

[TOC](#toc---table-of-contents)


## Requirements

To run this example you will need to have Swift and Vapor toolbox installed. If you don't have then please follow the Vapor official installation instructions:

* [Linux](https://docs.vapor.codes/4.0/install/linux/)
* [macOS](https://docs.vapor.codes/4.0/install/macos/)

[TOC](#toc---table-of-contents)


## Try It

Now, run this example from the `/src/unprotected-server/hello` folder with:

```text
vapor run serve --port 8002
```

> **NOTE:** If running from inside a docker container then you need to add `--hostname 0.0.0.0` to the end of the command.

Finally, you can test that it works with:

```text
curl -iX GET 'http://localhost:8002'
```

The response will be:

```text
HTTP/1.1 200 OK
content-type: application/json; charset=utf-8
content-length: 27
connection: keep-alive
date: Fri, 18 Sep 2020 14:41:35 GMT

{"message":"Hello, World!"}
```

[TOC](#toc---table-of-contents)
