importScripts("https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: 'AIzaSyAvTSJIReXOpASFEbZZuL-ZAwsSqCOmZOQ',
  appId: '1:889517767998:web:eaffecb7f00797daaa806f',
  messagingSenderId: '889517767998',
  projectId: 'aeroride-665af',
  authDomain: 'aeroride-665af.firebaseapp.com',
  storageBucket: 'aeroride-665af.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/favicon.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
