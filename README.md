Disclaimer: Please note that we no longer support older versions of SDKs and Modules. We recommend that the latest versions are used.

# README

# Contents

- Introduction
- Prerequisites
- Using the Gateway SDK
- License

# Introduction

This Ruby SDK provides an easy method to integrate with the payment gateway.
 - The gateway.rb file contains the main body of the SDK.
 - The sample.rb file is intended as a minimal guide to demonstrate a complete 3DSv2 authentication process.

# Prerequisites

- The SDK requires the following prerequisites to be met in order to function correctly:
    - Ruby v2.7+
    - _htmlentities_ gem (`gem install htmlentities`)

> Please note that we can only offer support for the SDK itself. While every effort has been made to ensure the sample code is complete and bug free, it is only a guide and should not be used in a production environment.

# Using the Gateway SDK

Instantiate the Gateway object ensuring you pass in your Merchant ID and secret key.

```
gateway = Gateway.new(env, "100856", "Circle4Take40Idea")
```

This is a minimal object creation, but you can also override the default _direct_, _hosted_ and _merchant password_ fields, should you need to. The object also supports proxying if you require it. Take a look at gateway.rb to see the full method signatures

Once your object has been created. You create your request array, for example:

```
reqFields = {
      "merchantID" => "100856",
      "action" => "SALE",
      "type" => 1,
      "transactionUnique" => uniqid,
      "countryCode" => 826,
      "currencyCode" => 826,
      "amount" => 1001,
      "cardNumber" => "XXXXXXXXXXXXXXXX",
      "cardExpiryMonth" => XX,
      "cardExpiryYear" => XX,
      "cardCVV" => "XXX",
      "customerName" => "Test Customer",
      "customerEmail" => "test@testcustomer.com",
      "customerAddress" => "30 Test Street",
      "customerPostcode" => "TE15 5ST",
      "orderRef" => "Test purchase",
      # The following fields are mandatory for 3DS v2
      "remoteAddress" => remoteAddress,
      "merchantCategoryCode" => 5411,
      "threeDSVersion" => "2",
      "threeDSRedirectURL" => pageUrl + "&acs=1",
    }
```

> NB: This is a sample request. The gateway features many more options. Please see our integration guides for more details.
Then, depending on your integration method, you'd either call:

```
gateway.directRequest(reqFields)
```

OR

```
gateway.hostedRequest(reqFields)
```

And then handle the response received from the gateway.

License
----
MIT
