// CargoBayTests.m
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me/)
// Created by Stan Chang Khin Boon on 12/14/2012.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <StoreKit/StoreKit.h>

#import "CargoBayTests.h"

#import "CargoBay.h"
#import "AFNetworking.h"

@protocol _CargoBay <NSObject>
@optional
+ (NSString *)_base64EncodedStringFromData:(NSData *)data;
+ (NSData *)_dataFromBase64EncodedString:(NSString *)base64EncodedString;
+ (BOOL)_validateTrust:(SecTrustRef)trust
                 error:(NSError * __autoreleasing *)error;
+ (BOOL)_validatePurchaseInfo:(NSDictionary *)purchaseInfo
               matchesReceipt:(NSDictionary *)receipt
                        error:(NSError * __autoreleasing *)error;
+ (BOOL)_validateTransaction:(SKPaymentTransaction *)transaction
         matchesPurchaseInfo:(NSDictionary *)purchaseInfoDictionary
                       error:(NSError * __autoreleasing *)error;
+ (BOOL)_checkReceiptSecurityWithPurchaseInfo:(NSString *)purchaseInfoString
                                    signature:(NSString *)signatureString
                                 purchaseDate:(NSDate *)purchaseDate;
+ (NSDictionary *)_purchaseInfoFromTransactionReceipt:(NSData *)transactionReceiptData
                                                error:(NSError * __autoreleasing *)error;
@end

@interface CargoBay (Private) <_CargoBay>
@property (readwrite, nonatomic, strong) AFHTTPClient *sandboxReceiptVerificationClient;
@property (readwrite, nonatomic, strong) AFHTTPClient *productionReceiptVerificationClient;
@end

@implementation CargoBay (Private)
@dynamic sandboxReceiptVerificationClient;
@dynamic productionReceiptVerificationClient;

extern NSString * CBBase64EncodedStringFromData(NSData *);
extern NSData * CBDataFromBase64EncodedString(NSString *);
extern BOOL CBValidateTrust(SecTrustRef, NSError * __autoreleasing *);
extern BOOL CBValidatePurchaseInfoMatchesReceipt(NSDictionary *, NSDictionary *, NSError * __autoreleasing *);
extern BOOL CBValidateTransactionMatchesPurchaseInfo(SKPaymentTransaction *, NSDictionary *, NSError * __autoreleasing *);
extern BOOL CBCheckReceiptSecurity(NSString *, NSString *, NSDate *);
extern NSDictionary * CBPurchaseInfoFromTransactionReceipt(NSData *,  NSError * __autoreleasing *);

+ (NSString *)_base64EncodedStringFromData:(NSData *)data {
    return CBBase64EncodedStringFromData(data);
}

+ (NSData *)_dataFromBase64EncodedString:(NSString *)base64EncodedString {
    return CBDataFromBase64EncodedString(base64EncodedString);
}

+ (BOOL)_validateTrust:(SecTrustRef)trust
                 error:(NSError * __autoreleasing *)error
{
    return CBValidateTrust(trust, error);
}

+ (BOOL)_validatePurchaseInfo:(NSDictionary *)purchaseInfo
               matchesReceipt:(NSDictionary *)receipt
                        error:(NSError * __autoreleasing *)error
{
    return CBValidatePurchaseInfoMatchesReceipt(purchaseInfo, receipt, error);
}

+ (BOOL)_validateTransaction:(SKPaymentTransaction *)transaction
         matchesPurchaseInfo:(NSDictionary *)purchaseInfoDictionary
                       error:(NSError * __autoreleasing *)error
{
    return CBValidateTransactionMatchesPurchaseInfo(transaction, purchaseInfoDictionary, error);
}

+ (BOOL)_checkReceiptSecurityWithPurchaseInfo:(NSString *)purchaseInfoString
                                    signature:(NSString *)signatureString
                                 purchaseDate:(NSDate *)purchaseDate
{
    return CBCheckReceiptSecurity(purchaseInfoString, signatureString, purchaseDate);
}

+ (NSDictionary *)_purchaseInfoFromTransactionReceipt:(NSData *)transactionReceiptData error:(NSError * __autoreleasing *)error {
    return CBPurchaseInfoFromTransactionReceipt(transactionReceiptData, error);
}

@end

#pragma mark -

@interface MockSKPaymentTransaction : NSObject <NSCopying>
@property NSError *error;
@property SKPaymentTransaction *originalTransaction;
@property SKPayment *payment;
@property NSArray *downloads;
@property NSDate *transactionDate;
@property NSString *transactionIdentifier;
@property NSData *transactionReceipt;
@property SKPaymentTransactionState transactionState;
@end

@implementation MockSKPaymentTransaction

- (id)copyWithZone:(NSZone *)zone {
    __typeof(self) copy = [[[self class] allocWithZone:zone] init];
    if (!copy) {
        return nil;
    }

    copy.error = [self.error copyWithZone:zone];
    copy.originalTransaction = self.originalTransaction;
    copy.error = [self.error copyWithZone:zone];
    copy.payment = [self.payment copyWithZone:zone];
    copy.downloads = [self.downloads copyWithZone:zone];
    copy.transactionDate = [self.transactionDate copyWithZone:zone];
    copy.transactionIdentifier = [self.transactionIdentifier copyWithZone:zone];
    copy.transactionReceipt = [self.transactionReceipt copyWithZone:zone];
    copy.transactionState = self.transactionState;

    return copy;
}

@end

@implementation CargoBayTests

- (void)dispatchSemaphoreInBlock:(void (^)(void (^resume)(void)))block {
    __block BOOL keepRunning = YES;
    block(^{ keepRunning = NO; });
    while (keepRunning && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]) {}
}

#pragma mark -

- (void)testBase64EncodingAndDecoding {
    // [From Wikipedia: A quote from Thomas Hobbes' Leviathan](http://en.wikipedia.org/wiki/Base64)
    {
        NSData *decoded = [@"Man is distinguished, not only by his reason, but by this singular passion from other animals, which is a lust of the mind, that by a perseverance of delight in the continued and indefatigable generation of knowledge, exceeds the short vehemence of any carnal pleasure." dataUsingEncoding:NSUTF8StringEncoding];
        
        NSString *encoded = @"TWFuIGlzIGRpc3Rpbmd1aXNoZWQsIG5vdCBvbmx5IGJ5IGhpcyByZWFzb24sIGJ1dCBieSB0aGlzIHNpbmd1bGFyIHBhc3Npb24gZnJvbSBvdGhlciBhbmltYWxzLCB3aGljaCBpcyBhIGx1c3Qgb2YgdGhlIG1pbmQsIHRoYXQgYnkgYSBwZXJzZXZlcmFuY2Ugb2YgZGVsaWdodCBpbiB0aGUgY29udGludWVkIGFuZCBpbmRlZmF0aWdhYmxlIGdlbmVyYXRpb24gb2Yga25vd2xlZGdlLCBleGNlZWRzIHRoZSBzaG9ydCB2ZWhlbWVuY2Ugb2YgYW55IGNhcm5hbCBwbGVhc3VyZS4=";
        
        // Encodes
        {
            NSString *output = [CargoBay _base64EncodedStringFromData:decoded];
            
            STAssertEqualObjects(encoded, output, @"The result should be equal.");
        }
        
        // Decodes
        {
            NSData *output = [CargoBay _dataFromBase64EncodedString:encoded];
            
            STAssertEqualObjects(decoded, output, @"The result should be equal.");
        }
    }
    
    
    // [From Wikipedia: Lorem ipsum](http://en.wikipedia.org/wiki/Lorem_ipsum)
    {
        NSData *decoded = [@"Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum." dataUsingEncoding:NSUTF8StringEncoding];
        
        NSString *encoded = @"TG9yZW0gaXBzdW0gZG9sb3Igc2l0IGFtZXQsIGNvbnNlY3RldHVyIGFkaXBpc2ljaW5nIGVsaXQsIHNlZCBkbyBlaXVzbW9kIHRlbXBvciBpbmNpZGlkdW50IHV0IGxhYm9yZSBldCBkb2xvcmUgbWFnbmEgYWxpcXVhLiBVdCBlbmltIGFkIG1pbmltIHZlbmlhbSwgcXVpcyBub3N0cnVkIGV4ZXJjaXRhdGlvbiB1bGxhbWNvIGxhYm9yaXMgbmlzaSB1dCBhbGlxdWlwIGV4IGVhIGNvbW1vZG8gY29uc2VxdWF0LiBEdWlzIGF1dGUgaXJ1cmUgZG9sb3IgaW4gcmVwcmVoZW5kZXJpdCBpbiB2b2x1cHRhdGUgdmVsaXQgZXNzZSBjaWxsdW0gZG9sb3JlIGV1IGZ1Z2lhdCBudWxsYSBwYXJpYXR1ci4gRXhjZXB0ZXVyIHNpbnQgb2NjYWVjYXQgY3VwaWRhdGF0IG5vbiBwcm9pZGVudCwgc3VudCBpbiBjdWxwYSBxdWkgb2ZmaWNpYSBkZXNlcnVudCBtb2xsaXQgYW5pbSBpZCBlc3QgbGFib3J1bS4=";
        
        // Encodes
        {
            NSString *output = [CargoBay _base64EncodedStringFromData:decoded];
            
            STAssertEqualObjects(encoded, output, @"The result should be equal.");
        }
        
        // Decodes
        {
            NSData *output = [CargoBay _dataFromBase64EncodedString:encoded];
            
            STAssertEqualObjects(decoded, output, @"The result should be equal.");
        }
    }
    
    
    // [Sample receipt from Sandbox Server](https://gist.github.com/4187607)
    // Plist is generated using OpenStep format which is not available for writing.
    {
        NSData *decoded = [@"{\n	\"signature\" = \"AkYuPMDg5n9y40Q/jWOO/UNJyFAo3cO+oRjIZIKYt7/M05EyXqJNHJGPQnmda4Zy0BqGsz1m2fpSJQatT03V/b0TfAr4+p8bofURjCLY9NX36LCgWDjwS1SxRao+4ek72q53MeGVSkGoy5E27jSz5P2fQds8PvwPid3Dx3O594/wAAADVzCCA1MwggI7oAMCAQICCGUUkU3ZWAS1MA0GCSqGSIb3DQEBBQUAMH8xCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEzMDEGA1UEAwwqQXBwbGUgaVR1bmVzIFN0b3JlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTA5MDYxNTIyMDU1NloXDTE0MDYxNDIyMDU1NlowZDEjMCEGA1UEAwwaUHVyY2hhc2VSZWNlaXB0Q2VydGlmaWNhdGUxGzAZBgNVBAsMEkFwcGxlIGlUdW5lcyBTdG9yZTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMrRjF2ct4IrSdiTChaI0g8pwv/cmHs8p/RwV/rt/91XKVhNl4XIBimKjQQNfgHsDs6yju++DrKJE7uKsphMddKYfFE5rGXsAdBEjBwRIxexTevx3HLEFGAt1moKx509dhxtiIdDgJv2YaVs49B0uJvNdy6SMqNNLHsDLzDS9oZHAgMBAAGjcjBwMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAUNh3o4p2C0gEYtTJrDtdDC5FYQzowDgYDVR0PAQH/BAQDAgeAMB0GA1UdDgQWBBSpg4PyGUjFPhJXCBTMzaN+mV8k9TAQBgoqhkiG92NkBgUBBAIFADANBgkqhkiG9w0BAQUFAAOCAQEAEaSbPjtmN4C/IB3QEpK32RxacCDXdVXAeVReS5FaZxc+t88pQP93BiAxvdW/3eTSMGY5FbeAYL3etqP5gm8wrFojX0ikyVRStQ+/AQ0KEjtqB07kLs9QUe8czR8UGfdM1EumV/UgvDd4NwNYxLQMg4WTQfgkQQVy8GXZwVHgbE/UC6Y7053pGXBk51NPM3woxhd3gSRLvXj+loHsStcTEqe9pBDpmG5+sk4tw+GK3GMeEN5/+e1QT9np/Kl1nj+aBw7C0xsy0bFnaAd1cSS6xdory/CUvM6gtKsmnOOdqTesbp0bs8sn6Wqs0C9dgcxRHuOMZ2tm8npLUm7argOSzQ==\";\n	\"purchase-info\" = \"ewoJIm9yaWdpbmFsLXB1cmNoYXNlLWRhdGUtcHN0IiA9ICIyMDEyLTEyLTAxIDIzOjE1OjU0IEFtZXJpY2EvTG9zX0FuZ2VsZXMiOwoJInB1cmNoYXNlLWRhdGUtbXMiID0gIjEzNTQ0MzI1NTQwMDAiOwoJInVuaXF1ZS1pZGVudGlmaWVyIiA9ICIwMDAwYjAwOTI4MTgiOwoJIm9yaWdpbmFsLXRyYW5zYWN0aW9uLWlkIiA9ICIxMDAwMDAwMDU5NjMyMzg1IjsKCSJleHBpcmVzLWRhdGUiID0gIjEzNTQ0MzYxNTQwMDAiOwoJInRyYW5zYWN0aW9uLWlkIiA9ICIxMDAwMDAwMDU5NjMyMzg1IjsKCSJvcmlnaW5hbC1wdXJjaGFzZS1kYXRlLW1zIiA9ICIxMzU0NDMyNTU0MDAwIjsKCSJ3ZWItb3JkZXItbGluZS1pdGVtLWlkIiA9ICIxMDAwMDAwMDI2NDM2MjkwIjsKCSJidnJzIiA9ICI3IjsKCSJleHBpcmVzLWRhdGUtZm9ybWF0dGVkLXBzdCIgPSAiMjAxMi0xMi0wMiAwMDoxNTo1NCBBbWVyaWNhL0xvc19BbmdlbGVzIjsKCSJpdGVtLWlkIiA9ICI1ODAxOTM5MzciOwoJImV4cGlyZXMtZGF0ZS1mb3JtYXR0ZWQiID0gIjIwMTItMTItMDIgMDg6MTU6NTQgRXRjL0dNVCI7CgkicHJvZHVjdC1pZCIgPSAiY29tLmRfX2J1enouZ2FnX3BsdXMuaW9zLjAwMS5hcnMucHJlbWl1bS4xeSI7CgkicHVyY2hhc2UtZGF0ZSIgPSAiMjAxMi0xMi0wMiAwNzoxNTo1NCBFdGMvR01UIjsKCSJvcmlnaW5hbC1wdXJjaGFzZS1kYXRlIiA9ICIyMDEyLTEyLTAyIDA3OjE1OjU0IEV0Yy9HTVQiOwoJImJpZCIgPSAiY29tLmQtLWJ1enouZ2FnLXBsdXMuaW9zLjAwMSI7CgkicHVyY2hhc2UtZGF0ZS1wc3QiID0gIjIwMTItMTItMDEgMjM6MTU6NTQgQW1lcmljYS9Mb3NfQW5nZWxlcyI7CgkicXVhbnRpdHkiID0gIjEiOwp9\";\n	\"environment\" = \"Sandbox\";\n	\"pod\" = \"100\";\n	\"signing-status\" = \"0\";\n}" dataUsingEncoding:NSUTF8StringEncoding];
        
        NSString *encoded = @"ewoJInNpZ25hdHVyZSIgPSAiQWtZdVBNRGc1bjl5NDBRL2pXT08vVU5KeUZBbzNjTytvUmpJWklLWXQ3L00wNUV5WHFKTkhKR1BRbm1kYTRaeTBCcUdzejFtMmZwU0pRYXRUMDNWL2IwVGZBcjQrcDhib2ZVUmpDTFk5TlgzNkxDZ1dEandTMVN4UmFvKzRlazcycTUzTWVHVlNrR295NUUyN2pTejVQMmZRZHM4UHZ3UGlkM0R4M081OTQvd0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeUxUQXhJREl6T2pFMU9qVTBJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRME16STFOVFF3TURBaU93b0pJblZ1YVhGMVpTMXBaR1Z1ZEdsbWFXVnlJaUE5SUNJd01EQXdZakF3T1RJNE1UZ2lPd29KSW05eWFXZHBibUZzTFhSeVlXNXpZV04wYVc5dUxXbGtJaUE5SUNJeE1EQXdNREF3TURVNU5qTXlNemcxSWpzS0NTSmxlSEJwY21WekxXUmhkR1VpSUQwZ0lqRXpOVFEwTXpZeE5UUXdNREFpT3dvSkluUnlZVzV6WVdOMGFXOXVMV2xrSWlBOUlDSXhNREF3TURBd01EVTVOak15TXpnMUlqc0tDU0p2Y21sbmFXNWhiQzF3ZFhKamFHRnpaUzFrWVhSbExXMXpJaUE5SUNJeE16VTBORE15TlRVME1EQXdJanNLQ1NKM1pXSXRiM0prWlhJdGJHbHVaUzFwZEdWdExXbGtJaUE5SUNJeE1EQXdNREF3TURJMk5ETTJNamt3SWpzS0NTSmlkbkp6SWlBOUlDSTNJanNLQ1NKbGVIQnBjbVZ6TFdSaGRHVXRabTl5YldGMGRHVmtMWEJ6ZENJZ1BTQWlNakF4TWkweE1pMHdNaUF3TURveE5UbzFOQ0JCYldWeWFXTmhMMHh2YzE5QmJtZGxiR1Z6SWpzS0NTSnBkR1Z0TFdsa0lpQTlJQ0kxT0RBeE9UTTVNemNpT3dvSkltVjRjR2x5WlhNdFpHRjBaUzFtYjNKdFlYUjBaV1FpSUQwZ0lqSXdNVEl0TVRJdE1ESWdNRGc2TVRVNk5UUWdSWFJqTDBkTlZDSTdDZ2tpY0hKdlpIVmpkQzFwWkNJZ1BTQWlZMjl0TG1SZlgySjFlbm91WjJGblgzQnNkWE11YVc5ekxqQXdNUzVoY25NdWNISmxiV2wxYlM0eGVTSTdDZ2tpY0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNaTB3TWlBd056b3hOVG8xTkNCRmRHTXZSMDFVSWpzS0NTSnZjbWxuYVc1aGJDMXdkWEpqYUdGelpTMWtZWFJsSWlBOUlDSXlNREV5TFRFeUxUQXlJREEzT2pFMU9qVTBJRVYwWXk5SFRWUWlPd29KSW1KcFpDSWdQU0FpWTI5dExtUXRMV0oxZW5vdVoyRm5MWEJzZFhNdWFXOXpMakF3TVNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TURFZ01qTTZNVFU2TlRRZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpY1hWaGJuUnBkSGtpSUQwZ0lqRWlPd3A5IjsKCSJlbnZpcm9ubWVudCIgPSAiU2FuZGJveCI7CgkicG9kIiA9ICIxMDAiOwoJInNpZ25pbmctc3RhdHVzIiA9ICIwIjsKfQ==";
        
        // Encodes
        {
            NSString *output = [CargoBay _base64EncodedStringFromData:decoded];
            
            STAssertEqualObjects(encoded, output, @"The result should be equal.");
        }
        
        // Decodes
        {
            NSData *output = [CargoBay _dataFromBase64EncodedString:encoded];
            STAssertEqualObjects(decoded, output, @"The result should be equal.");
        }
    }
}

- (void)testValidateTrust {
    // https://buy.itunes.apple.com/ have extended validation (EV) certificate.
    [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
        AFHTTPClient *client = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:@"https://buy.itunes.apple.com/"]];
        
        NSURLRequest *request = [client requestWithMethod:@"GET" path:@"" parameters:nil];
        AFHTTPRequestOperation *operation = [client HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
            resume();
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            STFail(@"The network operation should not fail.");
            resume();
        }];
        
        [operation setWillSendRequestForAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
            if ([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
                SecTrustRef trust = [[challenge protectionSpace] serverTrust];
                NSError *error = nil;

                BOOL didUseCredential = NO;
                BOOL isTrusted = [CargoBay _validateTrust:trust error:&error];
                STAssertTrue(isTrusted, @"The result should be true.");
                if (isTrusted) {
                    NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
                    if (credential) {
                        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                        didUseCredential = YES;
                    }
                }

                if (!didUseCredential) {
                    [[challenge sender] cancelAuthenticationChallenge:challenge];
                }
            } else {
                [[challenge sender] performDefaultHandlingForAuthenticationChallenge:challenge];
            }
        }];
        
        [client enqueueHTTPRequestOperation:operation];
    }];
    
    // https://www.apple.com/ does not have extended validation (EV) certificate.
    [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
        AFHTTPClient *client = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:@"https://www.apple.com/"]];
        
        NSURLRequest *request = [client requestWithMethod:@"GET" path:@"" parameters:nil];
        AFHTTPRequestOperation *operation = [client HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
            STFail(@"The network operation should not be able to succeed.");
            resume();
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            resume();
        }];
        
        [operation setWillSendRequestForAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
            if ([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
                SecTrustRef trust = [[challenge protectionSpace] serverTrust];
                NSError *error = nil;
                
                BOOL didUseCredential = NO;
                BOOL isTrusted = [CargoBay _validateTrust:trust error:&error];
                STAssertFalse(isTrusted, @"The result should be true.");
                if (isTrusted) {
                    NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
                    if (credential) {
                        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                        didUseCredential = YES;
                    }
                }
                
                if (!didUseCredential) {
                    [[challenge sender] cancelAuthenticationChallenge:challenge];
                }
            } else {
                [[challenge sender] performDefaultHandlingForAuthenticationChallenge:challenge];
            }
        }];
        
        [client enqueueHTTPRequestOperation:operation];
    }];
}

- (void)testValidatePurchaseInfoMatchesReceipt {
    NSDictionary *purchaseInfo = @{
        @"original-purchase-date-pst" : @"2012-12-01 23:15:54 America/Los_Angeles",
        @"purchase-date-ms" : @"1354432554000",
        @"unique-identifier" : @"0000b0092818",
        @"original-transaction-id" : @"1000000059632385",
        @"expires-date" : @"1354436154000",
        @"transaction-id" : @"1000000059632385",
        @"original-purchase-date-ms" : @"1354432554000",
        @"web-order-line-item-id" : @"1000000026436290",
        @"bvrs" : @"7",
        @"expires-date-formatted-pst" : @"2012-12-02 00:15:54 America/Los_Angeles",
        @"item-id" : @"580193937",
        @"expires-date-formatted" : @"2012-12-02 08:15:54 Etc/GMT",
        @"product-id" : @"com.d__buzz.gag_plus.ios.001.ars.premium.1y",
        @"purchase-date" : @"2012-12-02 07:15:54 Etc/GMT",
        @"original-purchase-date" : @"2012-12-02 07:15:54 Etc/GMT",
        @"bid" : @"com.d--buzz.gag-plus.ios.001",
        @"purchase-date-pst" : @"2012-12-01 23:15:54 America/Los_Angeles",
        @"quantity" : @"1"
    };
    
    NSDictionary *receipt = @{
        @"original_purchase_date_ms" : @"1354432554000",
        @"original_purchase_date_pst" : @"2012-12-01 23:15:54 America/Los_Angeles",
        @"transaction_id" : @"1000000059632385",
        @"quantity" : @"1",
        @"bid" : @"com.d--buzz.gag-plus.ios.001",
        @"original_transaction_id" : @"1000000059632385",
        @"bvrs" : @"7",
        @"expires_date_formatted" : @"2012-12-02 08:15:54 Etc/GMT",
        @"purchase_date" : @"2012-12-02 07:15:54 Etc/GMT",
        @"expires_date" : @"1354436154000",
        @"product_id" : @"com.d__buzz.gag_plus.ios.001.ars.premium.1y",
        @"purchase_date_ms" : @"1354432554000",
        @"expires_date_formatted_pst" : @"2012-12-02 00:15:54 America/Los_Angeles",
        @"purchase_date_pst" : @"2012-12-01 23:15:54 America/Los_Angeles",
        @"original_purchase_date" : @"2012-12-02 07:15:54 Etc/GMT",
        @"item_id" : @"580193937",
        @"web_order_line_item_id" : @"1000000026436290",
        @"unique_identifier" : @"0000b0092818"
    };
    
    if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"identifierForVendor")]) {
#if (__IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1)
        NSString *deviceIdentifierForVendor = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"unique-vendor-identifier"] = deviceIdentifierForVendor;
        purchaseInfo = [mutablePurchaseInfo copy];
        
        NSMutableDictionary *mutableReceipt = [receipt mutableCopy];
        mutableReceipt[@"unique_vendor_identifier"] = deviceIdentifierForVendor;
        receipt = [mutableReceipt copy];
#endif
    } else if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"uniqueIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSString *deviceIdentifier = [[[UIDevice currentDevice] identifierForVendor] description];
#pragma clang diagnostic pop
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"unique-identifier"] = deviceIdentifier;
        purchaseInfo = [mutablePurchaseInfo copy];
        
        NSMutableDictionary *mutableReceipt = [receipt mutableCopy];
        mutableReceipt[@"unique_identifier"] = deviceIdentifier;
        receipt = [mutableReceipt copy];
    }
    
    {
        NSError *error = nil;
        STAssertFalse([CargoBay _validatePurchaseInfo:nil matchesReceipt:nil error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
    
    {
        NSError *error = nil;
        STAssertFalse([CargoBay _validatePurchaseInfo:nil matchesReceipt:receipt error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
    
    {
        NSError *error = nil;
        STAssertFalse([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:nil error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
    
    {
        NSError *error = nil;
        STAssertTrue([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:receipt error:&error], @"The result should be true.");
        STAssertNil(error, @"The result should be nil.");
    }
    
    {
        NSError *error = nil;
        
        NSMutableDictionary *mutableReceipt = [receipt mutableCopy];
        mutableReceipt[@"bid"] = @"com.example.app";
        STAssertFalse([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:mutableReceipt error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
    
    {
        NSError *error = nil;
        
        NSMutableDictionary *mutableReceipt = [receipt mutableCopy];
        mutableReceipt[@"product_id"] = @"com.example.app.ars.premium.1y";
        STAssertFalse([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:mutableReceipt error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
    
    {
        NSError *error = nil;
        
        NSMutableDictionary *mutableReceipt = [receipt mutableCopy];
        mutableReceipt[@"quantity"] = @"2";
        STAssertFalse([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:mutableReceipt error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
    
#if !TARGET_IPHONE_SIMULATOR
    {
        NSError *error = nil;
        
        NSMutableDictionary *mutableReceipt = [receipt mutableCopy];
        mutableReceipt[@"unique_identifier"] = @"";
        mutableReceipt[@"unique_vendor_identifier"] = @"";
        STAssertFalse([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:mutableReceipt error:&error], @"The result should be true.");
        STAssertNotNil(error, @"The result should not be nil.");
        STAssertEquals(error.code, CargoBayErrorPurchaseInfoDoesNotMatchReceipt, @"The result should be equal.");
    }
#endif
}

- (void)testValidateTransactionMatchesPurchaseInfo {
    NSDictionary *purchaseInfo = @{
        @"original-purchase-date-pst" : @"2012-12-01 23:15:54 America/Los_Angeles",
        @"purchase-date-ms" : @"1354432554000",
        @"unique-identifier" : @"0000b0092818",
        @"original-transaction-id" : @"1000000059632385",
        @"expires-date" : @"1354436154000",
        @"transaction-id" : @"1000000059632385",
        @"original-purchase-date-ms" : @"1354432554000",
        @"web-order-line-item-id" : @"1000000026436290",
        @"bvrs" : @"7",
        @"expires-date-formatted-pst" : @"2012-12-02 00:15:54 America/Los_Angeles",
        @"item-id" : @"580193937",
        @"expires-date-formatted" : @"2012-12-02 08:15:54 Etc/GMT",
        @"product-id" : @"com.d__buzz.gag_plus.ios.001.ars.premium.1y",
        @"purchase-date" : @"2012-12-02 07:15:54 Etc/GMT",
        @"original-purchase-date" : @"2012-12-02 07:15:54 Etc/GMT",
        @"bid" : @"com.d--buzz.gag-plus.ios.001",
        @"purchase-date-pst" : @"2012-12-01 23:15:54 America/Los_Angeles",
        @"quantity" : @"1"
    };
    
    MockSKPaymentTransaction *mockSKPaymentTransaction = [[MockSKPaymentTransaction alloc] init];
    mockSKPaymentTransaction.error = nil;
    mockSKPaymentTransaction.originalTransaction = nil;
    SKMutablePayment *mutablePayment = [[SKMutablePayment alloc] init];
    mutablePayment.productIdentifier = purchaseInfo[@"product-id"];
    mutablePayment.quantity = [purchaseInfo[@"quantity"] integerValue];
    mockSKPaymentTransaction.payment = mutablePayment;
    mockSKPaymentTransaction.downloads = nil;
    NSString *purchaseInfoPurchaseDateString = purchaseInfo[@"purchase-date"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss z";
    NSDate *purchaseInfoPurchaseDate = [dateFormatter dateFromString:[purchaseInfoPurchaseDateString stringByReplacingOccurrencesOfString:@"Etc/" withString:@""]];
    mockSKPaymentTransaction.transactionDate = purchaseInfoPurchaseDate;
    mockSKPaymentTransaction.transactionIdentifier = purchaseInfo[@"transaction-id"];
    mockSKPaymentTransaction.transactionReceipt =  [CargoBay _dataFromBase64EncodedString:@"ewoJInNpZ25hdHVyZSIgPSAiQWtZdVBNRGc1bjl5NDBRL2pXT08vVU5KeUZBbzNjTytvUmpJWklLWXQ3L00wNUV5WHFKTkhKR1BRbm1kYTRaeTBCcUdzejFtMmZwU0pRYXRUMDNWL2IwVGZBcjQrcDhib2ZVUmpDTFk5TlgzNkxDZ1dEandTMVN4UmFvKzRlazcycTUzTWVHVlNrR295NUUyN2pTejVQMmZRZHM4UHZ3UGlkM0R4M081OTQvd0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeUxUQXhJREl6T2pFMU9qVTBJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRME16STFOVFF3TURBaU93b0pJblZ1YVhGMVpTMXBaR1Z1ZEdsbWFXVnlJaUE5SUNJd01EQXdZakF3T1RJNE1UZ2lPd29KSW05eWFXZHBibUZzTFhSeVlXNXpZV04wYVc5dUxXbGtJaUE5SUNJeE1EQXdNREF3TURVNU5qTXlNemcxSWpzS0NTSmxlSEJwY21WekxXUmhkR1VpSUQwZ0lqRXpOVFEwTXpZeE5UUXdNREFpT3dvSkluUnlZVzV6WVdOMGFXOXVMV2xrSWlBOUlDSXhNREF3TURBd01EVTVOak15TXpnMUlqc0tDU0p2Y21sbmFXNWhiQzF3ZFhKamFHRnpaUzFrWVhSbExXMXpJaUE5SUNJeE16VTBORE15TlRVME1EQXdJanNLQ1NKM1pXSXRiM0prWlhJdGJHbHVaUzFwZEdWdExXbGtJaUE5SUNJeE1EQXdNREF3TURJMk5ETTJNamt3SWpzS0NTSmlkbkp6SWlBOUlDSTNJanNLQ1NKbGVIQnBjbVZ6TFdSaGRHVXRabTl5YldGMGRHVmtMWEJ6ZENJZ1BTQWlNakF4TWkweE1pMHdNaUF3TURveE5UbzFOQ0JCYldWeWFXTmhMMHh2YzE5QmJtZGxiR1Z6SWpzS0NTSnBkR1Z0TFdsa0lpQTlJQ0kxT0RBeE9UTTVNemNpT3dvSkltVjRjR2x5WlhNdFpHRjBaUzFtYjNKdFlYUjBaV1FpSUQwZ0lqSXdNVEl0TVRJdE1ESWdNRGc2TVRVNk5UUWdSWFJqTDBkTlZDSTdDZ2tpY0hKdlpIVmpkQzFwWkNJZ1BTQWlZMjl0TG1SZlgySjFlbm91WjJGblgzQnNkWE11YVc5ekxqQXdNUzVoY25NdWNISmxiV2wxYlM0eGVTSTdDZ2tpY0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNaTB3TWlBd056b3hOVG8xTkNCRmRHTXZSMDFVSWpzS0NTSnZjbWxuYVc1aGJDMXdkWEpqYUdGelpTMWtZWFJsSWlBOUlDSXlNREV5TFRFeUxUQXlJREEzT2pFMU9qVTBJRVYwWXk5SFRWUWlPd29KSW1KcFpDSWdQU0FpWTI5dExtUXRMV0oxZW5vdVoyRm5MWEJzZFhNdWFXOXpMakF3TVNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TURFZ01qTTZNVFU2TlRRZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpY1hWaGJuUnBkSGtpSUQwZ0lqRWlPd3A5IjsKCSJlbnZpcm9ubWVudCIgPSAiU2FuZGJveCI7CgkicG9kIiA9ICIxMDAiOwoJInNpZ25pbmctc3RhdHVzIiA9ICIwIjsKfQ=="];
    mockSKPaymentTransaction.transactionState = SKPaymentTransactionStatePurchased;
    
    {
        SKPaymentTransaction *paymentTransaction = (SKPaymentTransaction *)mockSKPaymentTransaction;
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"bid"] = [NSBundle mainBundle].bundleIdentifier;
        
        {
            NSError *error = nil;
            STAssertTrue([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be true.");
        }
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:nil matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:nil error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:nil matchesPurchaseInfo:nil error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
    }
    
    {
        SKPaymentTransaction *paymentTransaction = (SKPaymentTransaction *)mockSKPaymentTransaction;
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"bid"] = [NSBundle mainBundle].bundleIdentifier;
        
        mutablePurchaseInfo[@"product-id"] = @"com.example.app.ars.premium.1y";
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
    }
    
    {
        SKPaymentTransaction *paymentTransaction = (SKPaymentTransaction *)mockSKPaymentTransaction;
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"bid"] = [NSBundle mainBundle].bundleIdentifier;
        
        mutablePurchaseInfo[@"quantity"] = @"2";
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
    }
    
    {
        SKPaymentTransaction *paymentTransaction = (SKPaymentTransaction *)mockSKPaymentTransaction;
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"bid"] = [NSBundle mainBundle].bundleIdentifier;
        
        mutablePurchaseInfo[@"transaction-id"] = @"";
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
    }
    
    {
        SKPaymentTransaction *paymentTransaction = (SKPaymentTransaction *)mockSKPaymentTransaction;
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"bid"] = [NSBundle mainBundle].bundleIdentifier;
        
        mutablePurchaseInfo[@"bid"] = @"com.example.app";
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
    }
    
    {
        SKPaymentTransaction *paymentTransaction = (SKPaymentTransaction *)mockSKPaymentTransaction;
        
        NSMutableDictionary *mutablePurchaseInfo = [purchaseInfo mutableCopy];
        mutablePurchaseInfo[@"bid"] = [NSBundle mainBundle].bundleIdentifier;
        
        mutablePurchaseInfo[@"purchase-date"] = @"2012-12-02 07:15:00 Etc/GMT";
        
        {
            NSError *error = nil;
            STAssertFalse([CargoBay _validateTransaction:paymentTransaction matchesPurchaseInfo:mutablePurchaseInfo error:&error], @"The result should be false.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorTransactionDoesNotMatchesPurchaseInfo, @"The result should be equal.");
        }
    }
}

- (void)testCheckReceiptSecurity {
    NSString *signatureString = @"AkYuPMDg5n9y40Q/jWOO/UNJyFAo3cO+oRjIZIKYt7/M05EyXqJNHJGPQnmda4Zy0BqGsz1m2fpSJQatT03V/b0TfAr4+p8bofURjCLY9NX36LCgWDjwS1SxRao+4ek72q53MeGVSkGoy5E27jSz5P2fQds8PvwPid3Dx3O594/wAAADVzCCA1MwggI7oAMCAQICCGUUkU3ZWAS1MA0GCSqGSIb3DQEBBQUAMH8xCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEzMDEGA1UEAwwqQXBwbGUgaVR1bmVzIFN0b3JlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTA5MDYxNTIyMDU1NloXDTE0MDYxNDIyMDU1NlowZDEjMCEGA1UEAwwaUHVyY2hhc2VSZWNlaXB0Q2VydGlmaWNhdGUxGzAZBgNVBAsMEkFwcGxlIGlUdW5lcyBTdG9yZTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMrRjF2ct4IrSdiTChaI0g8pwv/cmHs8p/RwV/rt/91XKVhNl4XIBimKjQQNfgHsDs6yju++DrKJE7uKsphMddKYfFE5rGXsAdBEjBwRIxexTevx3HLEFGAt1moKx509dhxtiIdDgJv2YaVs49B0uJvNdy6SMqNNLHsDLzDS9oZHAgMBAAGjcjBwMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAUNh3o4p2C0gEYtTJrDtdDC5FYQzowDgYDVR0PAQH/BAQDAgeAMB0GA1UdDgQWBBSpg4PyGUjFPhJXCBTMzaN+mV8k9TAQBgoqhkiG92NkBgUBBAIFADANBgkqhkiG9w0BAQUFAAOCAQEAEaSbPjtmN4C/IB3QEpK32RxacCDXdVXAeVReS5FaZxc+t88pQP93BiAxvdW/3eTSMGY5FbeAYL3etqP5gm8wrFojX0ikyVRStQ+/AQ0KEjtqB07kLs9QUe8czR8UGfdM1EumV/UgvDd4NwNYxLQMg4WTQfgkQQVy8GXZwVHgbE/UC6Y7053pGXBk51NPM3woxhd3gSRLvXj+loHsStcTEqe9pBDpmG5+sk4tw+GK3GMeEN5/+e1QT9np/Kl1nj+aBw7C0xsy0bFnaAd1cSS6xdory/CUvM6gtKsmnOOdqTesbp0bs8sn6Wqs0C9dgcxRHuOMZ2tm8npLUm7argOSzQ==";
    NSString *purchaseInfoString = @"ewoJIm9yaWdpbmFsLXB1cmNoYXNlLWRhdGUtcHN0IiA9ICIyMDEyLTEyLTAxIDIzOjE1OjU0IEFtZXJpY2EvTG9zX0FuZ2VsZXMiOwoJInB1cmNoYXNlLWRhdGUtbXMiID0gIjEzNTQ0MzI1NTQwMDAiOwoJInVuaXF1ZS1pZGVudGlmaWVyIiA9ICIwMDAwYjAwOTI4MTgiOwoJIm9yaWdpbmFsLXRyYW5zYWN0aW9uLWlkIiA9ICIxMDAwMDAwMDU5NjMyMzg1IjsKCSJleHBpcmVzLWRhdGUiID0gIjEzNTQ0MzYxNTQwMDAiOwoJInRyYW5zYWN0aW9uLWlkIiA9ICIxMDAwMDAwMDU5NjMyMzg1IjsKCSJvcmlnaW5hbC1wdXJjaGFzZS1kYXRlLW1zIiA9ICIxMzU0NDMyNTU0MDAwIjsKCSJ3ZWItb3JkZXItbGluZS1pdGVtLWlkIiA9ICIxMDAwMDAwMDI2NDM2MjkwIjsKCSJidnJzIiA9ICI3IjsKCSJleHBpcmVzLWRhdGUtZm9ybWF0dGVkLXBzdCIgPSAiMjAxMi0xMi0wMiAwMDoxNTo1NCBBbWVyaWNhL0xvc19BbmdlbGVzIjsKCSJpdGVtLWlkIiA9ICI1ODAxOTM5MzciOwoJImV4cGlyZXMtZGF0ZS1mb3JtYXR0ZWQiID0gIjIwMTItMTItMDIgMDg6MTU6NTQgRXRjL0dNVCI7CgkicHJvZHVjdC1pZCIgPSAiY29tLmRfX2J1enouZ2FnX3BsdXMuaW9zLjAwMS5hcnMucHJlbWl1bS4xeSI7CgkicHVyY2hhc2UtZGF0ZSIgPSAiMjAxMi0xMi0wMiAwNzoxNTo1NCBFdGMvR01UIjsKCSJvcmlnaW5hbC1wdXJjaGFzZS1kYXRlIiA9ICIyMDEyLTEyLTAyIDA3OjE1OjU0IEV0Yy9HTVQiOwoJImJpZCIgPSAiY29tLmQtLWJ1enouZ2FnLXBsdXMuaW9zLjAwMSI7CgkicHVyY2hhc2UtZGF0ZS1wc3QiID0gIjIwMTItMTItMDEgMjM6MTU6NTQgQW1lcmljYS9Mb3NfQW5nZWxlcyI7CgkicXVhbnRpdHkiID0gIjEiOwp9";

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss z";
    NSDate *purchaseDate = [dateFormatter dateFromString:@"2012-12-02 07:15:54 GMT"];
    
    /*
     Apple iTunes Store Certification Authority
     Not Valid After: 18/05/2016 18:31:30 GMT (1463596290)
     
     -----BEGIN CERTIFICATE-----
     MIIGHjCCBQagAwIBAgIQLEjdkw31WY75PJlUemDtQzANBgkqhkiG9w0BAQUFADCB
     yjELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQL
     ExZWZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTowOAYDVQQLEzEoYykgMjAwNiBWZXJp
     U2lnbiwgSW5jLiAtIEZvciBhdXRob3JpemVkIHVzZSBvbmx5MUUwQwYDVQQDEzxW
     ZXJpU2lnbiBDbGFzcyAzIFB1YmxpYyBQcmltYXJ5IENlcnRpZmljYXRpb24gQXV0
     aG9yaXR5IC0gRzUwHhcNMDYxMTA4MDAwMDAwWhcNMTYxMTA3MjM1OTU5WjCBvjEL
     MAkGA1UEBhMCVVMxFzAVBgNVBAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZW
     ZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTswOQYDVQQLEzJUZXJtcyBvZiB1c2UgYXQg
     aHR0cHM6Ly93d3cudmVyaXNpZ24uY29tL3JwYSAoYykwNjE4MDYGA1UEAxMvVmVy
     aVNpZ24gQ2xhc3MgMyBFeHRlbmRlZCBWYWxpZGF0aW9uIFNTTCBTR0MgQ0EwggEi
     MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC9Voi6iDRkZM/NyrDu5xlzxXLZ
     u0W8taj/g74cA9vtibcuEBolvFXKQaGfC88ZXnC5XjlLnjEcX4euKqqoK6IbOxAj
     XxOx3QiMThTag4HjtYzjaO0kZ85Wtqybc5ZE24qMs9bwcZOO23FUSutzWWqPcFEs
     A5+X0cwRerxiDZUqyRx1V+n1x+q6hDXLx4VafuRN4RGXfQ4gNEXb8aIJ6+s9nriW
     Q140SwglHkMaotm3igE0PcP45a9PjP/NZfAjTsWXs1zakByChQ0GDcEitnsopAPD
     TFPRWLxyvAg5/KB2qKjpS26IPeOzMSWMcylIDjJ5Bu09Q/T25On8fb6OCNUfAgMB
     AAGjggIIMIICBDAdBgNVHQ4EFgQUTkPIHXbvN1N6T/JYb5TzOOLVvd8wEgYDVR0T
     AQH/BAgwBgEB/wIBADA9BgNVHSAENjA0MDIGBFUdIAAwKjAoBggrBgEFBQcCARYc
     aHR0cHM6Ly93d3cudmVyaXNpZ24uY29tL2NwczA9BgNVHR8ENjA0MDKgMKAuhixo
     dHRwOi8vRVZTZWN1cmUtY3JsLnZlcmlzaWduLmNvbS9wY2EzLWc1LmNybDAOBgNV
     HQ8BAf8EBAMCAQYwEQYJYIZIAYb4QgEBBAQDAgEGMG0GCCsGAQUFBwEMBGEwX6Fd
     oFswWTBXMFUWCWltYWdlL2dpZjAhMB8wBwYFKw4DAhoEFI/l0xqGrI2Oa8PPgGrU
     SBgsexkuMCUWI2h0dHA6Ly9sb2dvLnZlcmlzaWduLmNvbS92c2xvZ28uZ2lmMCkG
     A1UdEQQiMCCkHjAcMRowGAYDVQQDExFDbGFzczNDQTIwNDgtMS00ODAfBgNVHSME
     GDAWgBR/02Wnwt3su/AwCfNDOfoCrzMxMzA9BggrBgEFBQcBAQQxMC8wLQYIKwYB
     BQUHMAGGIWh0dHA6Ly9FVlNlY3VyZS1vY3NwLnZlcmlzaWduLmNvbTA0BgNVHSUE
     LTArBglghkgBhvhCBAEGCmCGSAGG+EUBCAEGCCsGAQUFBwMBBggrBgEFBQcDAjAN
     BgkqhkiG9w0BAQUFAAOCAQEAJ3SmNOodneFT1hydDKdbTKln8vAytwEP+0IYON7k
     7knIE8kL7ATDQHEYcnZDAiNdq3vISBQayHsd/PYKnzah0glzcWaWdVE0v5kwUWed
     VLcmRaxzCCOGJplx9I7X6jmbBgkjv2LdqMS2faSJBz7zba5AWVB5lzc9Mnh9smNL
     +eoIaQ4T7ejPu6wFhsoiz4hiXTwiSdhj1SSmve9c48wgOyLq/ETGqOUf4YbNDE2P
     k1PZf+6hCKezMJZJcG6jbD3QY+8lZmPMqrcYF07qcHb2ukKmgDcJTp9miC5rM2bI
     wHGkQeta4/wULkuI/a5uW2XpJ+S/5LAjwbJ9W2Il1z4Q1A==
     -----END CERTIFICATE-----
     */
    
    /*
     Purchase Receipt Certificate (The certificate extracted from the signature)
     Not Valid After: 14/06/2014 22:05:56 GMT (1402783556)
     
     -----BEGIN CERTIFICATE-----
     MIIDUzCCAjugAwIBAgIIZRSRTdlYBLUwDQYJKoZIhvcNAQEFBQAwfzELMAkGA1UE
     BhMCVVMxEzARBgNVBAoMCkFwcGxlIEluYy4xJjAkBgNVBAsMHUFwcGxlIENlcnRp
     ZmljYXRpb24gQXV0aG9yaXR5MTMwMQYDVQQDDCpBcHBsZSBpVHVuZXMgU3RvcmUg
     Q2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMDkwNjE1MjIwNTU2WhcNMTQwNjE0
     MjIwNTU2WjBkMSMwIQYDVQQDDBpQdXJjaGFzZVJlY2VpcHRDZXJ0aWZpY2F0ZTEb
     MBkGA1UECwwSQXBwbGUgaVR1bmVzIFN0b3JlMRMwEQYDVQQKDApBcHBsZSBJbmMu
     MQswCQYDVQQGEwJVUzCBnzANBgkqhkiG9w0BAQEFAAOBjQAwgYkCgYEAytGMXZy3
     gitJ2JMKFojSDynC/9yYezyn9HBX+u3/3VcpWE2XhcgGKYqNBA1+AewOzrKO774O
     sokTu4qymEx10ph8UTmsZewB0ESMHBEjF7FN6/HccsQUYC3WagrHnT12HG2Ih0OA
     m/ZhpWzj0HS4m813LpIyo00sewMvMNL2hkcCAwEAAaNyMHAwDAYDVR0TAQH/BAIw
     ADAfBgNVHSMEGDAWgBQ2HejinYLSARi1MmsO10MLkVhDOjAOBgNVHQ8BAf8EBAMC
     B4AwHQYDVR0OBBYEFKmDg/IZSMU+ElcIFMzNo36ZXyT1MBAGCiqGSIb3Y2QGBQEE
     AgUAMA0GCSqGSIb3DQEBBQUAA4IBAQARpJs+O2Y3gL8gHdASkrfZHFpwINd1VcB5
     VF5LkVpnFz63zylA/3cGIDG91b/d5NIwZjkVt4Bgvd62o/mCbzCsWiNfSKTJVFK1
     D78BDQoSO2oHTuQuz1BR7xzNHxQZ90zUS6ZX9SC8N3g3A1jEtAyDhZNB+CRBBXLw
     ZdnBUeBsT9QLpjvTnekZcGTnU08zfCjGF3eBJEu9eP6WgexK1xMSp72kEOmYbn6y
     Ti3D4YrcYx4Q3n/57VBP2en8qXWeP5oHDsLTGzLRsWdoB3VxJLrF2ivL8JS8zqC0
     qyac452pN6xunRuzyyfpaqzQL12BzFEe44xna2byektSbtquA5LN
     -----END CERTIFICATE-----
     */
    
    STAssertTrue([CargoBay _checkReceiptSecurityWithPurchaseInfo:purchaseInfoString signature:signatureString purchaseDate:purchaseDate], @"The result should be true.");
    
    // If this fails, it is likely that the signature certificate have expired.
    // This means that Apple will have to sign it with a new certificate though.
    // Although the hardcoded intermediate certificate still have around 2 more
    // years of validity, care have to be taken to determine if Apple have
    // updated its intermediate certificate.
    STAssertTrue([CargoBay _checkReceiptSecurityWithPurchaseInfo:purchaseInfoString signature:signatureString purchaseDate:[NSDate date]], @"The result should be true.");

    STAssertTrue([CargoBay _checkReceiptSecurityWithPurchaseInfo:purchaseInfoString signature:signatureString purchaseDate:[NSDate dateWithTimeIntervalSince1970:1402783556.0]], @"The result should be true.");
    STAssertFalse([CargoBay _checkReceiptSecurityWithPurchaseInfo:purchaseInfoString signature:signatureString purchaseDate:[NSDate dateWithTimeIntervalSince1970:1402783557.0]], @"The result should be false.");
    
    {
        //NSString *purchaseInfoPlist = [[NSString alloc] initWithData:CBDataFromBase64EncodedString(purchaseInfoString) encoding:NSUTF8StringEncoding];
        NSString *purchaseInfoPlist = @"{\n	\"original-purchase-date-pst\" = \"2012-12-01 23:15:54 America/Los_Angeles\";\n	\"purchase-date-ms\" = \"1354432554000\";\n	\"unique-identifier\" = \"0000b0092818\";\n	\"original-transaction-id\" = \"1000000059632385\";\n	\"expires-date\" = \"1354436154000\";\n	\"transaction-id\" = \"1000000059632385\";\n	\"original-purchase-date-ms\" = \"1354432554000\";\n	\"web-order-line-item-id\" = \"1000000026436290\";\n	\"bvrs\" = \"7\";\n	\"expires-date-formatted-pst\" = \"2012-12-02 00:15:54 America/Los_Angeles\";\n	\"item-id\" = \"580193937\";\n	\"expires-date-formatted\" = \"2012-12-02 08:15:54 Etc/GMT\";\n	\"product-id\" = \"com.d__buzz.gag_plus.ios.001.ars.premium.1y\";\n	\"purchase-date\" = \"2012-12-02 07:15:54 Etc/GMT\";\n	\"original-purchase-date\" = \"2012-12-02 07:15:54 Etc/GMT\";\n	\"bid\" = \"com.d--buzz.gag-plus.ios.001\";\n	\"purchase-date-pst\" = \"2012-12-01 23:15:54 America/Los_Angeles\";\n	\"quantity\" = \"1\";\n}";
        NSString *purchaseInfoPlistBase64Encoded = [CargoBay _base64EncodedStringFromData:[purchaseInfoPlist dataUsingEncoding:NSUTF8StringEncoding]];
        STAssertTrue([CargoBay _checkReceiptSecurityWithPurchaseInfo:purchaseInfoPlistBase64Encoded signature:signatureString purchaseDate:purchaseDate], @"The result should be true.");
        purchaseInfoPlist = [purchaseInfoPlist stringByReplacingOccurrencesOfString:@"\"quantity\" = \"1\";" withString:@"\"quantity\" = \"9\";"];
        purchaseInfoPlistBase64Encoded = [CargoBay _base64EncodedStringFromData:[purchaseInfoPlist dataUsingEncoding:NSUTF8StringEncoding]];
        STAssertFalse([CargoBay _checkReceiptSecurityWithPurchaseInfo:purchaseInfoPlistBase64Encoded signature:signatureString purchaseDate:purchaseDate], @"The result should be false.");
    }
}

- (void)testPurchaseInfoFromTransactionReceipt {
    {
        NSString *receiptBase64EncodedString = @"ewoJInNpZ25hdHVyZSIgPSAiQWtZdVBNRGc1bjl5NDBRL2pXT08vVU5KeUZBbzNjTytvUmpJWklLWXQ3L00wNUV5WHFKTkhKR1BRbm1kYTRaeTBCcUdzejFtMmZwU0pRYXRUMDNWL2IwVGZBcjQrcDhib2ZVUmpDTFk5TlgzNkxDZ1dEandTMVN4UmFvKzRlazcycTUzTWVHVlNrR295NUUyN2pTejVQMmZRZHM4UHZ3UGlkM0R4M081OTQvd0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeUxUQXhJREl6T2pFMU9qVTBJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRME16STFOVFF3TURBaU93b0pJblZ1YVhGMVpTMXBaR1Z1ZEdsbWFXVnlJaUE5SUNJd01EQXdZakF3T1RJNE1UZ2lPd29KSW05eWFXZHBibUZzTFhSeVlXNXpZV04wYVc5dUxXbGtJaUE5SUNJeE1EQXdNREF3TURVNU5qTXlNemcxSWpzS0NTSmxlSEJwY21WekxXUmhkR1VpSUQwZ0lqRXpOVFEwTXpZeE5UUXdNREFpT3dvSkluUnlZVzV6WVdOMGFXOXVMV2xrSWlBOUlDSXhNREF3TURBd01EVTVOak15TXpnMUlqc0tDU0p2Y21sbmFXNWhiQzF3ZFhKamFHRnpaUzFrWVhSbExXMXpJaUE5SUNJeE16VTBORE15TlRVME1EQXdJanNLQ1NKM1pXSXRiM0prWlhJdGJHbHVaUzFwZEdWdExXbGtJaUE5SUNJeE1EQXdNREF3TURJMk5ETTJNamt3SWpzS0NTSmlkbkp6SWlBOUlDSTNJanNLQ1NKbGVIQnBjbVZ6TFdSaGRHVXRabTl5YldGMGRHVmtMWEJ6ZENJZ1BTQWlNakF4TWkweE1pMHdNaUF3TURveE5UbzFOQ0JCYldWeWFXTmhMMHh2YzE5QmJtZGxiR1Z6SWpzS0NTSnBkR1Z0TFdsa0lpQTlJQ0kxT0RBeE9UTTVNemNpT3dvSkltVjRjR2x5WlhNdFpHRjBaUzFtYjNKdFlYUjBaV1FpSUQwZ0lqSXdNVEl0TVRJdE1ESWdNRGc2TVRVNk5UUWdSWFJqTDBkTlZDSTdDZ2tpY0hKdlpIVmpkQzFwWkNJZ1BTQWlZMjl0TG1SZlgySjFlbm91WjJGblgzQnNkWE11YVc5ekxqQXdNUzVoY25NdWNISmxiV2wxYlM0eGVTSTdDZ2tpY0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNaTB3TWlBd056b3hOVG8xTkNCRmRHTXZSMDFVSWpzS0NTSnZjbWxuYVc1aGJDMXdkWEpqYUdGelpTMWtZWFJsSWlBOUlDSXlNREV5TFRFeUxUQXlJREEzT2pFMU9qVTBJRVYwWXk5SFRWUWlPd29KSW1KcFpDSWdQU0FpWTI5dExtUXRMV0oxZW5vdVoyRm5MWEJzZFhNdWFXOXpMakF3TVNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TURFZ01qTTZNVFU2TlRRZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpY1hWaGJuUnBkSGtpSUQwZ0lqRWlPd3A5IjsKCSJlbnZpcm9ubWVudCIgPSAiU2FuZGJveCI7CgkicG9kIiA9ICIxMDAiOwoJInNpZ25pbmctc3RhdHVzIiA9ICIwIjsKfQ==";
        NSData *receiptData = [CargoBay _dataFromBase64EncodedString:receiptBase64EncodedString];
        NSError *error = nil;
        NSDictionary *purchaseInfo = [CargoBay _purchaseInfoFromTransactionReceipt:receiptData error:&error];
        STAssertNotNil(purchaseInfo, @"The result should not be nil.");
        STAssertNil(error, @"The result should be nil.");
    }
    
    {
        NSString *receiptFormat = @"{\n	\"signature\" = \"%@\";\n	\"purchase-info\" = \"%@\";\n	\"environment\" = \"Sandbox\";\n	\"pod\" = \"100\";\n	\"signing-status\" = \"0\";\n}";
        NSString *signatureString = @"AkYuPMDg5n9y40Q/jWOO/UNJyFAo3cO+oRjIZIKYt7/M05EyXqJNHJGPQnmda4Zy0BqGsz1m2fpSJQatT03V/b0TfAr4+p8bofURjCLY9NX36LCgWDjwS1SxRao+4ek72q53MeGVSkGoy5E27jSz5P2fQds8PvwPid3Dx3O594/wAAADVzCCA1MwggI7oAMCAQICCGUUkU3ZWAS1MA0GCSqGSIb3DQEBBQUAMH8xCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEzMDEGA1UEAwwqQXBwbGUgaVR1bmVzIFN0b3JlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTA5MDYxNTIyMDU1NloXDTE0MDYxNDIyMDU1NlowZDEjMCEGA1UEAwwaUHVyY2hhc2VSZWNlaXB0Q2VydGlmaWNhdGUxGzAZBgNVBAsMEkFwcGxlIGlUdW5lcyBTdG9yZTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMrRjF2ct4IrSdiTChaI0g8pwv/cmHs8p/RwV/rt/91XKVhNl4XIBimKjQQNfgHsDs6yju++DrKJE7uKsphMddKYfFE5rGXsAdBEjBwRIxexTevx3HLEFGAt1moKx509dhxtiIdDgJv2YaVs49B0uJvNdy6SMqNNLHsDLzDS9oZHAgMBAAGjcjBwMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAUNh3o4p2C0gEYtTJrDtdDC5FYQzowDgYDVR0PAQH/BAQDAgeAMB0GA1UdDgQWBBSpg4PyGUjFPhJXCBTMzaN+mV8k9TAQBgoqhkiG92NkBgUBBAIFADANBgkqhkiG9w0BAQUFAAOCAQEAEaSbPjtmN4C/IB3QEpK32RxacCDXdVXAeVReS5FaZxc+t88pQP93BiAxvdW/3eTSMGY5FbeAYL3etqP5gm8wrFojX0ikyVRStQ+/AQ0KEjtqB07kLs9QUe8czR8UGfdM1EumV/UgvDd4NwNYxLQMg4WTQfgkQQVy8GXZwVHgbE/UC6Y7053pGXBk51NPM3woxhd3gSRLvXj+loHsStcTEqe9pBDpmG5+sk4tw+GK3GMeEN5/+e1QT9np/Kl1nj+aBw7C0xsy0bFnaAd1cSS6xdory/CUvM6gtKsmnOOdqTesbp0bs8sn6Wqs0C9dgcxRHuOMZ2tm8npLUm7argOSzQ==";
        NSString *purchaseInfoPlist = @"{\n	\"original-purchase-date-pst\" = \"2012-12-01 23:15:54 America/Los_Angeles\";\n	\"purchase-date-ms\" = \"1354432554000\";\n	\"unique-identifier\" = \"0000b0092818\";\n	\"original-transaction-id\" = \"1000000059632385\";\n	\"expires-date\" = \"1354436154000\";\n	\"transaction-id\" = \"1000000059632385\";\n	\"original-purchase-date-ms\" = \"1354432554000\";\n	\"web-order-line-item-id\" = \"1000000026436290\";\n	\"bvrs\" = \"7\";\n	\"expires-date-formatted-pst\" = \"2012-12-02 00:15:54 America/Los_Angeles\";\n	\"item-id\" = \"580193937\";\n	\"expires-date-formatted\" = \"2012-12-02 08:15:54 Etc/GMT\";\n	\"product-id\" = \"com.d__buzz.gag_plus.ios.001.ars.premium.1y\";\n	\"purchase-date\" = \"2012-12-02 07:15:54 Etc/GMT\";\n	\"original-purchase-date\" = \"2012-12-02 07:15:54 Etc/GMT\";\n	\"bid\" = \"com.d--buzz.gag-plus.ios.001\";\n	\"purchase-date-pst\" = \"2012-12-01 23:15:54 America/Los_Angeles\";\n	\"quantity\" = \"1\";\n}";
        
        
        {
            NSString *purchaseInfoString = [CargoBay _base64EncodedStringFromData:[purchaseInfoPlist dataUsingEncoding:NSUTF8StringEncoding]];
            NSString *receipt = [NSString stringWithFormat:receiptFormat, signatureString, purchaseInfoString];
            NSData *receiptData = [receipt dataUsingEncoding:NSUTF8StringEncoding];
            
            NSError *error = nil;
            NSDictionary *purchaseInfo = [CargoBay _purchaseInfoFromTransactionReceipt:receiptData error:&error];
            STAssertNotNil(purchaseInfo, @"The result should not be nil.");
            STAssertNil(error, @"The result should be nil.");
        }
        
        {
            purchaseInfoPlist = [purchaseInfoPlist stringByReplacingOccurrencesOfString:@"\"quantity\" = \"1\";" withString:@"\"quantity\" = \"9\";"];
            NSString *purchaseInfoString = [CargoBay _base64EncodedStringFromData:[purchaseInfoPlist dataUsingEncoding:NSUTF8StringEncoding]];
            NSString *receipt = [NSString stringWithFormat:receiptFormat, signatureString, purchaseInfoString];
            NSData *receiptData = [receipt dataUsingEncoding:NSUTF8StringEncoding];
            
            NSError *error = nil;
            NSDictionary *purchaseInfo = [CargoBay _purchaseInfoFromTransactionReceipt:receiptData error:&error];
            STAssertNil(purchaseInfo, @"The result should be nil.");
            STAssertNotNil(error, @"The result should not be nil.");
            STAssertEquals(error.code, CargoBayErrorCannotExtractPurchaseInfoFromTransactionReceipt, @"The result should be equal.");
        }
    }
}

- (void)testVerifyTransactionReceipt {
    {
        CargoBay *cargoBay = [[CargoBay alloc] init];
        
        // Checks for malfunction receipt data
        [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
            [cargoBay verifyTransactionWithMethod:@"POST" endpoint:[NSURL URLWithString:kCargoBaySandboxReceiptVerificationURLString] receipt:[NSData data] password:nil success:^(NSDictionary *responseObject) {
                STFail(@"The result should fail.");
                resume();
            } failure:^(NSError *error) {
                STAssertNotNil(error, @"The result should not be nil.");
                STAssertEquals(error.code, CargoBayErrorMalformedReceiptData, @"The result should be equal.");
                resume();
            }];
        }];
        
        // Checks for validating auto-renewable subscription transaction receipt without password.
        [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
            NSString *receiptBase64EncodedString = @"ewoJInNpZ25hdHVyZSIgPSAiQWtZdVBNRGc1bjl5NDBRL2pXT08vVU5KeUZBbzNjTytvUmpJWklLWXQ3L00wNUV5WHFKTkhKR1BRbm1kYTRaeTBCcUdzejFtMmZwU0pRYXRUMDNWL2IwVGZBcjQrcDhib2ZVUmpDTFk5TlgzNkxDZ1dEandTMVN4UmFvKzRlazcycTUzTWVHVlNrR295NUUyN2pTejVQMmZRZHM4UHZ3UGlkM0R4M081OTQvd0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeUxUQXhJREl6T2pFMU9qVTBJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRME16STFOVFF3TURBaU93b0pJblZ1YVhGMVpTMXBaR1Z1ZEdsbWFXVnlJaUE5SUNJd01EQXdZakF3T1RJNE1UZ2lPd29KSW05eWFXZHBibUZzTFhSeVlXNXpZV04wYVc5dUxXbGtJaUE5SUNJeE1EQXdNREF3TURVNU5qTXlNemcxSWpzS0NTSmxlSEJwY21WekxXUmhkR1VpSUQwZ0lqRXpOVFEwTXpZeE5UUXdNREFpT3dvSkluUnlZVzV6WVdOMGFXOXVMV2xrSWlBOUlDSXhNREF3TURBd01EVTVOak15TXpnMUlqc0tDU0p2Y21sbmFXNWhiQzF3ZFhKamFHRnpaUzFrWVhSbExXMXpJaUE5SUNJeE16VTBORE15TlRVME1EQXdJanNLQ1NKM1pXSXRiM0prWlhJdGJHbHVaUzFwZEdWdExXbGtJaUE5SUNJeE1EQXdNREF3TURJMk5ETTJNamt3SWpzS0NTSmlkbkp6SWlBOUlDSTNJanNLQ1NKbGVIQnBjbVZ6TFdSaGRHVXRabTl5YldGMGRHVmtMWEJ6ZENJZ1BTQWlNakF4TWkweE1pMHdNaUF3TURveE5UbzFOQ0JCYldWeWFXTmhMMHh2YzE5QmJtZGxiR1Z6SWpzS0NTSnBkR1Z0TFdsa0lpQTlJQ0kxT0RBeE9UTTVNemNpT3dvSkltVjRjR2x5WlhNdFpHRjBaUzFtYjNKdFlYUjBaV1FpSUQwZ0lqSXdNVEl0TVRJdE1ESWdNRGc2TVRVNk5UUWdSWFJqTDBkTlZDSTdDZ2tpY0hKdlpIVmpkQzFwWkNJZ1BTQWlZMjl0TG1SZlgySjFlbm91WjJGblgzQnNkWE11YVc5ekxqQXdNUzVoY25NdWNISmxiV2wxYlM0eGVTSTdDZ2tpY0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNaTB3TWlBd056b3hOVG8xTkNCRmRHTXZSMDFVSWpzS0NTSnZjbWxuYVc1aGJDMXdkWEpqYUdGelpTMWtZWFJsSWlBOUlDSXlNREV5TFRFeUxUQXlJREEzT2pFMU9qVTBJRVYwWXk5SFRWUWlPd29KSW1KcFpDSWdQU0FpWTI5dExtUXRMV0oxZW5vdVoyRm5MWEJzZFhNdWFXOXpMakF3TVNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TURFZ01qTTZNVFU2TlRRZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpY1hWaGJuUnBkSGtpSUQwZ0lqRWlPd3A5IjsKCSJlbnZpcm9ubWVudCIgPSAiU2FuZGJveCI7CgkicG9kIiA9ICIxMDAiOwoJInNpZ25pbmctc3RhdHVzIiA9ICIwIjsKfQ==";
            NSData *receiptData = [CargoBay _dataFromBase64EncodedString:receiptBase64EncodedString];

            [cargoBay verifyTransactionWithMethod:@"POST" endpoint:[NSURL URLWithString:kCargoBaySandboxReceiptVerificationURLString] receipt:receiptData password:nil success:^(NSDictionary *responseObject) {
                STFail(@"The result should fail.");
                resume();
            } failure:^(NSError *error) {
                STAssertNotNil(error, @"The result should not be nil.");
                STAssertEquals(error.code, CargoBayStatusSharedSecretDoesNotMatch, @"The result should be equal.");
                resume();
            }];
        }];
        
        // Checks (Sandbox) non-consumable transaction receipt on production server. Server should auto retry on sandbox server.
        [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
            NSString *receiptBase64EncodedString = @"ewoJInNpZ25hdHVyZSIgPSAiQW50d3ljU0tSOUpEVWZ6bWFaS0xGUVd2WU1TY3c2NlZ1aFAxbGhVMGZEVVZpZGwwUjdEdDR3bkVJY3I1N3BKSEM1T0FGNG10em02SFZ2UnBjWWg1eDZmMnNDSHBGZEdXa21RaHN5QzdFNFR0SEpheGRpZ2ZCNTFHdTRoUlp2dW1WVVB1K0VndFQ2cUFoUzgvVjZhUnJTYW1pVTdrbm5yUm1yZHRDN3liYUdlY0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeExUSTNJREEzT2pJMk9qUXlJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluVnVhWEYxWlMxcFpHVnVkR2xtYVdWeUlpQTlJQ0l3TURBd1lqQXpNV000TVRnaU93b0pJbTl5YVdkcGJtRnNMWFJ5WVc1ellXTjBhVzl1TFdsa0lpQTlJQ0l4TURBd01EQXdNRFU1TXpFNE5EWTRJanNLQ1NKaWRuSnpJaUE5SUNJNElqc0tDU0owY21GdWMyRmpkR2x2YmkxcFpDSWdQU0FpTVRBd01EQXdNREEyTURZNE16Y3dPQ0k3Q2draWNYVmhiblJwZEhraUlEMGdJakVpT3dvSkltOXlhV2RwYm1Gc0xYQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRd016QXdNREl3TURBaU93b0pJbkJ5YjJSMVkzUXRhV1FpSUQwZ0ltTnZiUzVrWDE5aWRYcDZMbWRoWjE5d2JIVnpMbWx2Y3k0d01ERXVibU11Y0hKbGJXbDFiU0k3Q2draWFYUmxiUzFwWkNJZ1BTQWlOVGd3TVRreE5qazRJanNLQ1NKaWFXUWlJRDBnSW1OdmJTNWtMUzFpZFhwNkxtZGhaeTF3YkhWekxtbHZjeTR3TURFaU93b0pJbkIxY21Ob1lYTmxMV1JoZEdVdGJYTWlJRDBnSWpFek5UVTRPVGt5TnpJME1EZ2lPd29KSW5CMWNtTm9ZWE5sTFdSaGRHVWlJRDBnSWpJd01USXRNVEl0TVRrZ01EWTZOREU2TVRJZ1JYUmpMMGROVkNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TVRnZ01qSTZOREU2TVRJZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpYjNKcFoybHVZV3d0Y0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNUzB5TnlBeE5Ub3lOam8wTWlCRmRHTXZSMDFVSWpzS2ZRPT0iOwoJImVudmlyb25tZW50IiA9ICJTYW5kYm94IjsKCSJwb2QiID0gIjEwMCI7Cgkic2lnbmluZy1zdGF0dXMiID0gIjAiOwp9";
            NSData *receiptData = [CargoBay _dataFromBase64EncodedString:receiptBase64EncodedString];

            [cargoBay verifyTransactionWithMethod:@"POST" endpoint:[NSURL URLWithString:kCargoBayProductionReceiptVerificationURLString] receipt:receiptData password:nil success:^(NSDictionary *responseObject) {
                STAssertNotNil(responseObject, @"The result should not be nil.");
                NSError *error = nil;
                NSDictionary *purchaseInfo = [CargoBay _purchaseInfoFromTransactionReceipt:receiptData error:&error];
                STAssertNil(error, @"The result should be nil.");
                STAssertNotNil(purchaseInfo, @"The result should not be nil.");
                NSDictionary *receipt = responseObject[@"receipt"];
                STAssertNotNil(receipt, @"The result should not be nil.");
                STAssertTrue([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:receipt error:&error], @"The result should be true.");
                STAssertNil(error, @"The result should be nil.");
                resume();
            } failure:^(NSError *error) {
                STFail(@"The result should not fail.");
                resume();
            }];
        }];
        
        // Checks (Sandbox) non-consumable transaction receipt on sandbox server.
        [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
            NSString *receiptBase64EncodedString = @"ewoJInNpZ25hdHVyZSIgPSAiQW50d3ljU0tSOUpEVWZ6bWFaS0xGUVd2WU1TY3c2NlZ1aFAxbGhVMGZEVVZpZGwwUjdEdDR3bkVJY3I1N3BKSEM1T0FGNG10em02SFZ2UnBjWWg1eDZmMnNDSHBGZEdXa21RaHN5QzdFNFR0SEpheGRpZ2ZCNTFHdTRoUlp2dW1WVVB1K0VndFQ2cUFoUzgvVjZhUnJTYW1pVTdrbm5yUm1yZHRDN3liYUdlY0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeExUSTNJREEzT2pJMk9qUXlJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluVnVhWEYxWlMxcFpHVnVkR2xtYVdWeUlpQTlJQ0l3TURBd1lqQXpNV000TVRnaU93b0pJbTl5YVdkcGJtRnNMWFJ5WVc1ellXTjBhVzl1TFdsa0lpQTlJQ0l4TURBd01EQXdNRFU1TXpFNE5EWTRJanNLQ1NKaWRuSnpJaUE5SUNJNElqc0tDU0owY21GdWMyRmpkR2x2YmkxcFpDSWdQU0FpTVRBd01EQXdNREEyTURZNE16Y3dPQ0k3Q2draWNYVmhiblJwZEhraUlEMGdJakVpT3dvSkltOXlhV2RwYm1Gc0xYQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRd016QXdNREl3TURBaU93b0pJbkJ5YjJSMVkzUXRhV1FpSUQwZ0ltTnZiUzVrWDE5aWRYcDZMbWRoWjE5d2JIVnpMbWx2Y3k0d01ERXVibU11Y0hKbGJXbDFiU0k3Q2draWFYUmxiUzFwWkNJZ1BTQWlOVGd3TVRreE5qazRJanNLQ1NKaWFXUWlJRDBnSW1OdmJTNWtMUzFpZFhwNkxtZGhaeTF3YkhWekxtbHZjeTR3TURFaU93b0pJbkIxY21Ob1lYTmxMV1JoZEdVdGJYTWlJRDBnSWpFek5UVTRPVGt5TnpJME1EZ2lPd29KSW5CMWNtTm9ZWE5sTFdSaGRHVWlJRDBnSWpJd01USXRNVEl0TVRrZ01EWTZOREU2TVRJZ1JYUmpMMGROVkNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TVRnZ01qSTZOREU2TVRJZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpYjNKcFoybHVZV3d0Y0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNUzB5TnlBeE5Ub3lOam8wTWlCRmRHTXZSMDFVSWpzS2ZRPT0iOwoJImVudmlyb25tZW50IiA9ICJTYW5kYm94IjsKCSJwb2QiID0gIjEwMCI7Cgkic2lnbmluZy1zdGF0dXMiID0gIjAiOwp9";
            NSData *receiptData = [CargoBay _dataFromBase64EncodedString:receiptBase64EncodedString];
            
            [cargoBay verifyTransactionWithMethod:@"POST" endpoint:[NSURL URLWithString:kCargoBayProductionReceiptVerificationURLString] receipt:receiptData password:nil success:^(NSDictionary *responseObject) {
                 STAssertNotNil(responseObject, @"The result should not be nil.");
                 NSError *error = nil;
                 NSDictionary *purchaseInfo = [CargoBay _purchaseInfoFromTransactionReceipt:receiptData error:&error];
                 STAssertNil(error, @"The result should be nil.");
                 STAssertNotNil(purchaseInfo, @"The result should not be nil.");
                 NSDictionary *receipt = responseObject[@"receipt"];
                 STAssertNotNil(receipt, @"The result should not be nil.");
                 STAssertTrue([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:receipt error:&error], @"The result should be true.");
                 STAssertNil(error, @"The result should be nil.");
                 resume();
             } failure:^(NSError *error) {
                 STFail(@"The result should not fail.");
                 resume();
             }];
        }];
        
        // Checks (Sandbox) non-consumable transaction receipt on sandbox server. Using public method.
        [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {
            NSString *receiptBase64EncodedString = @"ewoJInNpZ25hdHVyZSIgPSAiQW50d3ljU0tSOUpEVWZ6bWFaS0xGUVd2WU1TY3c2NlZ1aFAxbGhVMGZEVVZpZGwwUjdEdDR3bkVJY3I1N3BKSEM1T0FGNG10em02SFZ2UnBjWWg1eDZmMnNDSHBGZEdXa21RaHN5QzdFNFR0SEpheGRpZ2ZCNTFHdTRoUlp2dW1WVVB1K0VndFQ2cUFoUzgvVjZhUnJTYW1pVTdrbm5yUm1yZHRDN3liYUdlY0FBQURWekNDQTFNd2dnSTdvQU1DQVFJQ0NHVVVrVTNaV0FTMU1BMEdDU3FHU0liM0RRRUJCUVVBTUg4eEN6QUpCZ05WQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVNZd0pBWURWUVFMREIxQmNIQnNaU0JEWlhKMGFXWnBZMkYwYVc5dUlFRjFkR2h2Y21sMGVURXpNREVHQTFVRUF3d3FRWEJ3YkdVZ2FWUjFibVZ6SUZOMGIzSmxJRU5sY25ScFptbGpZWFJwYjI0Z1FYVjBhRzl5YVhSNU1CNFhEVEE1TURZeE5USXlNRFUxTmxvWERURTBNRFl4TkRJeU1EVTFObG93WkRFak1DRUdBMVVFQXd3YVVIVnlZMmhoYzJWU1pXTmxhWEIwUTJWeWRHbG1hV05oZEdVeEd6QVpCZ05WQkFzTUVrRndjR3hsSUdsVWRXNWxjeUJUZEc5eVpURVRNQkVHQTFVRUNnd0tRWEJ3YkdVZ1NXNWpMakVMTUFrR0ExVUVCaE1DVlZNd2daOHdEUVlKS29aSWh2Y05BUUVCQlFBRGdZMEFNSUdKQW9HQkFNclJqRjJjdDRJclNkaVRDaGFJMGc4cHd2L2NtSHM4cC9Sd1YvcnQvOTFYS1ZoTmw0WElCaW1LalFRTmZnSHNEczZ5anUrK0RyS0pFN3VLc3BoTWRkS1lmRkU1ckdYc0FkQkVqQndSSXhleFRldngzSExFRkdBdDFtb0t4NTA5ZGh4dGlJZERnSnYyWWFWczQ5QjB1SnZOZHk2U01xTk5MSHNETHpEUzlvWkhBZ01CQUFHamNqQndNQXdHQTFVZEV3RUIvd1FDTUFBd0h3WURWUjBqQkJnd0ZvQVVOaDNvNHAyQzBnRVl0VEpyRHRkREM1RllRem93RGdZRFZSMFBBUUgvQkFRREFnZUFNQjBHQTFVZERnUVdCQlNwZzRQeUdVakZQaEpYQ0JUTXphTittVjhrOVRBUUJnb3Foa2lHOTJOa0JnVUJCQUlGQURBTkJna3Foa2lHOXcwQkFRVUZBQU9DQVFFQUVhU2JQanRtTjRDL0lCM1FFcEszMlJ4YWNDRFhkVlhBZVZSZVM1RmFaeGMrdDg4cFFQOTNCaUF4dmRXLzNlVFNNR1k1RmJlQVlMM2V0cVA1Z204d3JGb2pYMGlreVZSU3RRKy9BUTBLRWp0cUIwN2tMczlRVWU4Y3pSOFVHZmRNMUV1bVYvVWd2RGQ0TndOWXhMUU1nNFdUUWZna1FRVnk4R1had1ZIZ2JFL1VDNlk3MDUzcEdYQms1MU5QTTN3b3hoZDNnU1JMdlhqK2xvSHNTdGNURXFlOXBCRHBtRzUrc2s0dHcrR0szR01lRU41LytlMVFUOW5wL0tsMW5qK2FCdzdDMHhzeTBiRm5hQWQxY1NTNnhkb3J5L0NVdk02Z3RLc21uT09kcVRlc2JwMGJzOHNuNldxczBDOWRnY3hSSHVPTVoydG04bnBMVW03YXJnT1N6UT09IjsKCSJwdXJjaGFzZS1pbmZvIiA9ICJld29KSW05eWFXZHBibUZzTFhCMWNtTm9ZWE5sTFdSaGRHVXRjSE4wSWlBOUlDSXlNREV5TFRFeExUSTNJREEzT2pJMk9qUXlJRUZ0WlhKcFkyRXZURzl6WDBGdVoyVnNaWE1pT3dvSkluVnVhWEYxWlMxcFpHVnVkR2xtYVdWeUlpQTlJQ0l3TURBd1lqQXpNV000TVRnaU93b0pJbTl5YVdkcGJtRnNMWFJ5WVc1ellXTjBhVzl1TFdsa0lpQTlJQ0l4TURBd01EQXdNRFU1TXpFNE5EWTRJanNLQ1NKaWRuSnpJaUE5SUNJNElqc0tDU0owY21GdWMyRmpkR2x2YmkxcFpDSWdQU0FpTVRBd01EQXdNREEyTURZNE16Y3dPQ0k3Q2draWNYVmhiblJwZEhraUlEMGdJakVpT3dvSkltOXlhV2RwYm1Gc0xYQjFjbU5vWVhObExXUmhkR1V0YlhNaUlEMGdJakV6TlRRd016QXdNREl3TURBaU93b0pJbkJ5YjJSMVkzUXRhV1FpSUQwZ0ltTnZiUzVrWDE5aWRYcDZMbWRoWjE5d2JIVnpMbWx2Y3k0d01ERXVibU11Y0hKbGJXbDFiU0k3Q2draWFYUmxiUzFwWkNJZ1BTQWlOVGd3TVRreE5qazRJanNLQ1NKaWFXUWlJRDBnSW1OdmJTNWtMUzFpZFhwNkxtZGhaeTF3YkhWekxtbHZjeTR3TURFaU93b0pJbkIxY21Ob1lYTmxMV1JoZEdVdGJYTWlJRDBnSWpFek5UVTRPVGt5TnpJME1EZ2lPd29KSW5CMWNtTm9ZWE5sTFdSaGRHVWlJRDBnSWpJd01USXRNVEl0TVRrZ01EWTZOREU2TVRJZ1JYUmpMMGROVkNJN0Nna2ljSFZ5WTJoaGMyVXRaR0YwWlMxd2MzUWlJRDBnSWpJd01USXRNVEl0TVRnZ01qSTZOREU2TVRJZ1FXMWxjbWxqWVM5TWIzTmZRVzVuWld4bGN5STdDZ2tpYjNKcFoybHVZV3d0Y0hWeVkyaGhjMlV0WkdGMFpTSWdQU0FpTWpBeE1pMHhNUzB5TnlBeE5Ub3lOam8wTWlCRmRHTXZSMDFVSWpzS2ZRPT0iOwoJImVudmlyb25tZW50IiA9ICJTYW5kYm94IjsKCSJwb2QiID0gIjEwMCI7Cgkic2lnbmluZy1zdGF0dXMiID0gIjAiOwp9";
            NSData *receiptData = [CargoBay _dataFromBase64EncodedString:receiptBase64EncodedString];
            
            [cargoBay verifyTransactionReceipt:receiptData password:nil success:^(NSDictionary *responseObject) {
                 STAssertNotNil(responseObject, @"The result should not be nil.");
                 NSError *error = nil;
                 NSDictionary *purchaseInfo = [CargoBay _purchaseInfoFromTransactionReceipt:receiptData error:&error];
                 STAssertNil(error, @"The result should be nil.");
                 STAssertNotNil(purchaseInfo, @"The result should not be nil.");
                 NSDictionary *receipt = responseObject[@"receipt"];
                 STAssertNotNil(receipt, @"The result should not be nil.");
                 STAssertTrue([CargoBay _validatePurchaseInfo:purchaseInfo matchesReceipt:receipt error:&error], @"The result should be true.");
                 STAssertNil(error, @"The result should be nil.");
                 resume();
             } failure:^(NSError *error) {
                 STFail(@"The result should not fail.");
                 resume();
             }];
        }];
        
        // TODO: Repeats the above checks for production server. Requires someone kind enough to share a production transaction receipt (for both Non-consumable and Auto-renewable subscription).
    }
}

- (void) testProductInvalidIdentifier;
{
    
    
    [self dispatchSemaphoreInBlock:^(void (^resume)(void)) {

        NSString *productid = @"invalid";
        NSSet *itemSet = [NSSet setWithObject:productid];

        [[CargoBay sharedManager] productsWithIdentifiers:itemSet success:^(NSArray *products, NSArray *invalidIdentifiers) {
            
            STAssertNotNil(invalidIdentifiers, @"Expected set of invalid ids.");
            STAssertTrue([invalidIdentifiers count] == 1, @"Expected one invalid id.");

            NSString *invalidid = [invalidIdentifiers lastObject];
            STAssertNotNil(invalidid, @"Expected invalid id to be defined.");
            STAssertTrue([invalidid isEqualToString:productid], @"Expected invalid id to be the same as the product id");
            resume();
        } failure:^(NSError *error) {
            STFail(@"The request should not fail.");
            resume();
        }];
    }];
    

}

@end
