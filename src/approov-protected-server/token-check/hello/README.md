# Approov Token Integration Example

This Approov integration example is from where the code example for the [Approov token check quickstart](/docs/APPROOV_TOKEN_QUICKSTART.md) is extracted, and you can use it as a playground to better understand how simple and easy it is to implement [Approov](https://approov.io) in a Swift Vapor API server.

## TOC - Table of Contents

* [Why?](#why)
* [How it Works?](#how-it-works)
* [Requirements](#requirements)
* [Setup Env File](#setup-env-file)
* [Try the Approov Integration Example](#try-the-approov-integration-example)


## Why?

To lock down your API server to your mobile app. Please read the brief summary in the [README](/README.md#why) at the root of this repo or visit our [website](https://approov.io/product.html) for more details.

[TOC](#toc---table-of-contents)


## How it works?

The Swift server is very simple and is defined in this Vapor project [/src/approov-protected-server/token-check/hello](/src/approov-protected-server/token-check/hello). Take a look at the [`verifyApproovToken()`](/src/approov-protected-server/token-check/hello/Sources/App/Middlewares/ApproovTokenMiddleware.swift) function to see the simple code for the check.

For more background on Approov, see the overview in the [README](/README.md#how-it-works) at the root of this repo.

[TOC](#toc---table-of-contents)


## Requirements

To run this example you will need to have Swift and Vapor toolbox installed. If you don't have then please follow the Vapor official installation instructions:

* [Linux](https://docs.vapor.codes/4.0/install/linux/)
* [macOS](https://docs.vapor.codes/4.0/install/macos/)

[TOC](#toc---table-of-contents)


## Setup Env File

From `/src/approov-protected-server/token-check/hello` execute the following:

```bash
cp .env.example .env
```

Edit the `.env` file and add the [dummy secret](/README.md#the-dummy-secret) to it in order to be able to test the Approov integration with the provided [Postman collection](https://github.com/approov/postman-collections/blob/master/quickstarts/hello-world/hello-world.postman_curl_requests_examples.md).

[TOC](#toc---table-of-contents)


## Try the Approov Integration Example

Now you can run this example from the `/src/approov-protected-server/token-check/hello` folder with:

```text
vapor run serve --port 8002
```

> **NOTE:** If running from inside a docker container then you need to add `--hostname 0.0.0.0` to the end of the command.

Next, you can test that it works with:

```bash
curl -iX GET 'http://localhost:8002'
```

The response will be a `401` unauthorized request:

```text
HTTP/1.1 401 Unauthorized
content-length: 38
content-type: application/json; charset=utf-8
connection: keep-alive
date: Thu, 24 Mar 2022 20:20:38 GMT

{"reason":"Unauthorized","error":true}
```

The reason you got a `401` is because the Approoov token isn't provided in the headers of the request.

Finally, you can test that the Approov integration example works as expected with this [Postman collection](/README.md#testing-with-postman) or with some cURL requests [examples](/README.md#testing-with-curl).

[TOC](#toc---table-of-contents)
