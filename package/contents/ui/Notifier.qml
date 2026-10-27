import QtQuick
import org.kde.notification

// Desktop notifications. Loaded by main.qml through a Loader, so a system without the
// KNotifications QML module still gets a working widget, just without notifications.
//
// One persistent Notification, owned by QML only (autoDelete: false), reused for every message.
// Creating one per message with autoDelete: true gave the object two owners (KNotification deletes
// it when it closes, QML deletes its children): a double free that can crash plasmashell.
Item {
    id: notifier

    Notification {
        id: notification
        componentName: "plasma_workspace"
        eventId: "notification"
        autoDelete: false
    }

    function send(title, text, iconName, critical) {
        notification.title = title;
        notification.text = text;
        notification.iconName = iconName;
        notification.urgency = critical ? Notification.HighUrgency : Notification.NormalUrgency;
        notification.sendEvent();
    }
}
