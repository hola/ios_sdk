var apn = require('apn');

// CONFIGURATION_START
var apnProvider = new apn.Provider({
     token: {
        key: '<key>.p8', // path to the key p8 file
        keyId: '<keyid>', // the Key ID of the p8 file (available at https://developer.apple.com/account/ios/certificate/key)
        teamId: '<teamid>', // the Team ID of your Apple Developer Account (available at https://developer.apple.com/account/#/membership/)
    },
    production: false // Set to true if sending a notification to a production iOS app
});
var deviceToken = '<devicetoken>'; // enter the device token from the Xcode console
// CONFIGURATION_END

var notification = new apn.Notification();
notification.topic = 'org.hola.hola-spark-demo2';
notification.category = 'spark-preview';
notification.expiry = Math.floor(Date.now() / 1000) + 3600;
notification.sound = 'ping.aiff';
notification.alert = {
    title: "Watch",
    body: "Dani Alves gets kicked out after shouting at referee in PSG defeat at Lyon",
};
notification.contentAvailable = true;
notification.mutableContent = true;
notification.payload = {
    "attachment-url": "https://video.h-cdn.com/static/mp4/preview_sample.mp4",
};

apnProvider.send(notification, deviceToken).then(function(result) {
    // Check the result for any failed devices
    console.log(result);
});
