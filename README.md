# CargoBay
**The Essential StoreKit Companion**

[`StoreKit`](http://developer.apple.com/library/ios/#documentation/StoreKit/Reference/StoreKit_Collection/) is the Apple framework for [making In-App Purchases](http://developer.apple.com/library/ios/#documentation/NetworkingInternet/Conceptual/StoreKitGuide/Introduction/Introduction.html). It's pretty good in its own right, but it has a few rough edges. 

`CargoBay` smooths out those rough parts by providing:

- Block-based interface for requesting product information
- Ability to request product information for identifiers asynchronously from a remote web service
- Block-based callbacks for payment queue observation delegate methods
- One-step receipt verification

## Usage

### Product Requests

```objective-c
NSArray *identifiers = @[
  @"com.example.myapp.apple",
  @"com.example.myapp.pear",
  @"com.example.myapp.banana"
];

[[CargoBay sharedManager] productsWithIdentifiers:[NSSet setWithArray:identifiers]
success:^(NSArray *products, NSArray *invalidIdentifiers) {
  NSLog(@"Products: %@", products);
  NSLog(@"Invalid Identifiers: %@", invalidIdentifiers);
} failure:^(NSError *error) {
  NSLog(@"Error: %@", error);
}];
```

### Getting Product Identifiers From Server

```objective-c
NSURL *URL = [NSURL URLWithString:@"http://example.com/products"];
[[CargoBay sharedManager] productsWithURLRequest:[NSURLRequest requestWithURL:URL]
success:^(NSArray *products, NSArray *invalidIdentifiers) {
  // ...
} failure:^(NSError *error) {
  // ...
}];
```

### Payment Queue Observation

**AppDelegate.m**

```objective-c
- (void)application:(UIApplication *)application didFinishLoadingWithOptions:(NSDictionary *)options {
  [[CargoBay sharedManager] setPaymentQueueUpdatedTransactionsBlock:^(SKPaymentQueue *queue, NSArray *transactions) {
    NSLog(@"Updated Transactions: %@", transactions);
  }];

  [[SKPaymentQueue defaultQueue] addTransactionObserver:[CargoBay sharedManager]];

  // ...
}
```

### Verifying Receipts

```objective-c
[[CargoBay sharedManager] verifyTransaction:(SKPaymentTransaction *) success:^(NSDictionary *receipt) {
  NSLog(@"Receipt: %@", receipt);
}
  failure:^(NSError *error) {
    NSLog(@"Error %d (%@)", [error code], [error localizedDescription]);
}];
```

### Contact

[Mattt Thompson](http://github.com/mattt)  
[@mattt](https://twitter.com/mattt)

## License

CargoBay is available under the MIT license. See the LICENSE file for more info.
