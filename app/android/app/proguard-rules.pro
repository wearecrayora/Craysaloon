# Razorpay Checkout (razorpay_flutter).
#
# The SDK is reached by reflection: its own classes, and the plugin's payment
# callbacks, are not referenced by name anywhere R8 can see. Without these keeps
# a minified RELEASE build strips them and the checkout sheet fails at the one
# moment that costs a real rupee - which is also the build nobody tests by hand.
#
# Listed now, while minification is off, so that turning it on at M13 is not the
# change that breaks payments.
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.** { *; }
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
-dontwarn com.razorpay.**
