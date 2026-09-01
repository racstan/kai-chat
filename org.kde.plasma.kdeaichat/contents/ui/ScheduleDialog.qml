import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

    QQC2.Dialog {
        id: scheduleDialog

        // Reference to the parent ConfigGeneral.qml page.
        // Must be set when instantiating: ScheduleDialog { id: scheduleDialog; page: page }
        // QML component files do NOT inherit id-namespace from parent files.
        property var page: null

        property int editingIndex: -1 // -2=new, >=0=edit, -1=list
        property var draft: ({
        })
        property string currentTab: "active"
        property var localActiveList: []
        property var localArchivedList: []
        property bool hasUnsavedChanges: false

        Timer {
            id: refreshTimer
            interval: 5000
            repeat: true
            running: scheduleDialog.opened && scheduleDialog.editingIndex === -1
            onTriggered: {
                if (page && typeof page.schedLoadSchedules === "function") {
                    page.schedLoadSchedules();
                }
            }
        }

        Connections {
            target: page
            ignoreUnknownSignals: true
            function onSchedulerListChanged() {
                console.log("ScheduleDialog: page.schedulerList changed, count =", page ? page.schedulerList.length : "null");
                if (scheduleDialog.opened && scheduleDialog.editingIndex === -1 && !scheduleDialog.hasUnsavedChanges) {
                    scheduleDialog.localActiveList = page.schedulerList.slice();
                    console.log("ScheduleDialog: updated localActiveList to count =", scheduleDialog.localActiveList.length);
                } else {
                    console.log("ScheduleDialog: skip localActiveList update (opened=" + scheduleDialog.opened + ", editingIndex=" + scheduleDialog.editingIndex + ", hasUnsavedChanges=" + scheduleDialog.hasUnsavedChanges + ")");
                }
            }
            function onSchedulerArchivedListChanged() {
                console.log("ScheduleDialog: page.schedulerArchivedList changed, count =", page ? page.schedulerArchivedList.length : "null");
                if (scheduleDialog.opened && scheduleDialog.editingIndex === -1 && !scheduleDialog.hasUnsavedChanges) {
                    scheduleDialog.localArchivedList = page.schedulerArchivedList.slice();
                }
            }
        }

        function translate(text) {
            return (page && typeof page.translate === "function") ? page.translate(text) : text;
        }

        function updateDraft(patch) {
            let d = Object.assign({}, draft);
            for (let k in patch) {
                d[k] = patch[k];
            }
            draft = d;
        }

        function saveAndSync() {
            if (page) {
                page.schedulerList = localActiveList;
                page.schedulerArchivedList = localArchivedList;
                scheduleDialog.hasUnsavedChanges = false;
                page.schedSaveAll();
            }
        }

        function getChatsList() {
            let raw = (typeof page !== "undefined" && page && page.cfg_chatSessionsJson) ? page.cfg_chatSessionsJson : "[]";
            try {
                let arr = JSON.parse(raw);
                let list = [];
                if (Array.isArray(arr)) {
                    for (let i = 0; i < arr.length; i++) {
                        if (arr[i] && arr[i].value && !arr[i].archived) {
                            let rawId = arr[i].value;
                            let displayId = rawId;
                            if (rawId.length > 10) {
                                displayId = rawId.substring(0, 8) + "...";
                            }
                            list.push({
                                "id": rawId,
                                "name": (arr[i].text || "Chat") + " (" + displayId + ")"
                            });
                        }
                    }
                }
                return list;
            } catch (e) {
                return [];
            }
        }

        // Helper: build cron from draft
        function buildCron(d) {
            if (d.taskType === "single")
                return "";

            let t = d.schedType || "days", n = parseInt(d.schedEvery) || 1;
            let sDate = new Date(d.startDate || new Date().toISOString());
            let hr = sDate.getHours(), mn = sDate.getMinutes();
            if (t === "minutes")
                return "*/" + n + " * * * *";

            if (t === "hours")
                return "0 */" + n + " * * *";

            if (t === "days")
                return (n === 1 ? mn + " " + hr + " * * *" : mn + " " + hr + " */" + n + " * *");

            if (t === "weeks") {
                let ds = (d.schedDays && d.schedDays.length > 0) ? d.schedDays.slice().sort().join(",") : "1";
                return mn + " " + hr + " * * " + ds;
            }
            if (t === "months") {
                let dom = d.schedDayOfMonth || 1;
                return (n === 1 ? mn + " " + hr + " " + dom + " * *" : mn + " " + hr + " " + dom + " */" + n + " *");
            }
            return "0 9 * * *";
        }

        function getStartYear(dateStr) {
            if (!dateStr)
                return new Date().getFullYear();

            return new Date(dateStr).getFullYear();
        }

        function getStartMonth(dateStr) {
            if (!dateStr)
                return new Date().getMonth();

            return new Date(dateStr).getMonth();
        }

        function getStartDay(dateStr) {
            if (!dateStr)
                return new Date().getDate();

            return new Date(dateStr).getDate();
        }

        function getStartHour(dateStr) {
            if (!dateStr)
                return 9;

            return new Date(dateStr).getHours();
        }

        function getStartMin(dateStr) {
            if (!dateStr)
                return 0;

            return new Date(dateStr).getMinutes();
        }

        function setStartDateField(field, value) {
            let d = new Date(scheduleDialog.draft.startDate || new Date().toISOString());
            d.setSeconds(0);
            d.setMilliseconds(0);
            if (field === "year")
                d.setFullYear(value);
            else if (field === "month")
                d.setMonth(value);
            else if (field === "day")
                d.setDate(value);
            else if (field === "hour")
                d.setHours(value);
            else if (field === "minute")
                d.setMinutes(value);
            scheduleDialog.updateDraft({"startDate": d.toISOString()});
        }

        // Helper: human-readable summary
        function humanText(d) {
            if (d.taskType === "single") {
                let sDate = new Date(d.startDate || new Date().toISOString());
                let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                let shr = sDate.getHours(), smn = sDate.getMinutes();
                let sap = shr >= 12 ? translate("PM") : translate("AM"), sh12 = shr % 12 || 12;
                let sms = smn < 10 ? "0" + smn : "" + smn;
                let stimeStr = sh12 + ":" + sms + " " + sap;
                return translate("Once on") + " " + translate(monthNames[sDate.getMonth()]) + " " + sDate.getDate() + ", " + sDate.getFullYear() + " " + translate("at") + " " + stimeStr;
            }
            let t = d.schedType || "days", n = parseInt(d.schedEvery) || 1;
            let sDate = new Date(d.startDate || new Date().toISOString());
            let hr = sDate.getHours(), mn = sDate.getMinutes();
            let ap = hr >= 12 ? translate("PM") : translate("AM"), h12 = hr % 12 || 12;
            let ms = mn < 10 ? "0" + mn : "" + mn;
            let timeStr = h12 + ":" + ms + " " + ap;
            let baseText = "";
            if (t === "minutes") {
                baseText = translate("Every") + " " + (n === 1 ? translate("minute") : n + " " + translate("minutes"));
            } else if (t === "hours") {
                baseText = translate("Every") + " " + (n === 1 ? translate("hour") : n + " " + translate("hours"));
            } else if (t === "days") {
                baseText = translate("Every") + " " + (n === 1 ? translate("day") : n + " " + translate("days")) + " " + translate("at") + " " + timeStr;
            } else if (t === "weeks") {
                let dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                let days = (d.schedDays && d.schedDays.length > 0) ? d.schedDays.map(function(x) {
                    return translate(dn[x]);
                }).join(", ") : translate("Mon");
                baseText = translate("Every") + " " + (n === 1 ? translate("week") : n + " " + translate("weeks")) + " " + translate("on") + " " + days + " " + translate("at") + " " + timeStr;
            } else if (t === "months") {
                let dom = d.schedDayOfMonth || 1;
                let sfx = dom === 1 ? translate("st") : dom === 2 ? translate("nd") : dom === 3 ? translate("rd") : translate("th");
                baseText = translate("Every") + " " + (n === 1 ? translate("month") : n + " " + translate("months")) + " " + translate("on the") + " " + dom + sfx + " " + translate("at") + " " + timeStr;
            }
            if (d.limitEnabled && d.limitCount)
                baseText += " (" + translate("Limit:") + " " + d.limitCount + " " + (d.limitCount === 1 ? translate("run") : translate("runs")) + ")";

            return baseText;
        }

        title: (editingIndex === -2) ? translate("Create Schedule") : ((editingIndex >= 0) ? translate("Edit Schedule") : translate("Schedules"))
        modal: true
        width: Kirigami.Units.gridUnit * 50
        height: Kirigami.Units.gridUnit * 46
        standardButtons: QQC2.Dialog.NoButton
        onOpened: {
            console.log("ScheduleDialog: onOpened triggered, current page.schedulerList count =", page ? page.schedulerList.length : "null");
            if (page) {
                page.schedLoadSchedules();
                scheduleDialog.hasUnsavedChanges = false;
                localActiveList = page.schedulerList.slice();
                localArchivedList = page.schedulerArchivedList.slice();
                console.log("ScheduleDialog: onOpened initialized lists: localActiveList count =", localActiveList.length);
            }
            if (editingIndex !== -2 && editingIndex < 0) {
                editingIndex = -1;
            }
        }
        onClosed: {
            editingIndex = -1;
        }

        // ── List view ──────────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            visible: scheduleDialog.editingIndex === -1

            // ── Segmented Tab Selector ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                
                QQC2.Button {
                    text: translate("Active") + " (" + scheduleDialog.localActiveList.length + ")"
                    icon.name: "appointment-new"
                    highlighted: scheduleDialog.currentTab === "active"
                    flat: scheduleDialog.currentTab !== "active"
                    Layout.fillWidth: true
                    onClicked: scheduleDialog.currentTab = "active"
                }

                QQC2.Button {
                    text: translate("Archived") + " (" + scheduleDialog.localArchivedList.length + ")"
                    icon.name: "archive-insert"
                    highlighted: scheduleDialog.currentTab === "archived"
                    flat: scheduleDialog.currentTab !== "archived"
                    Layout.fillWidth: true
                    onClicked: scheduleDialog.currentTab = "archived"
                }

                QQC2.Button {
                    text: translate("History") + " (" + page.schedulerHistory.length + ")"
                    icon.name: "view-history"
                    highlighted: scheduleDialog.currentTab === "history"
                    flat: scheduleDialog.currentTab !== "history"
                    Layout.fillWidth: true
                    onClicked: scheduleDialog.currentTab = "history"
                }
            }

            // ── Active Tab Header ──
            RowLayout {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "active"

                QQC2.Label {
                    text: scheduleDialog.localActiveList.length === 0 ? translate("No schedules configured yet") : (scheduleDialog.localActiveList.length === 1 ? translate("1 active schedule") : translate("%1 active schedules").arg(scheduleDialog.localActiveList.length))
                    opacity: 0.7
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: translate("New Schedule")
                    icon.name: "list-add"
                    highlighted: true
                    onClicked: {
                        let now = new Date();
                        now.setMinutes(now.getMinutes() + 5);
                        now.setSeconds(0);
                        now.setMilliseconds(0);
                        let chats = scheduleDialog.getChatsList();
                        let firstChatId = (chats.length > 0) ? chats[0].id : "";
                        let firstChatName = (chats.length > 0) ? chats[0].name : "";
                        scheduleDialog.draft = {
                            "id": page.schedMakeUuid(),
                            "name": "",
                            "enabled": true,
                            "chatId": firstChatId,
                            "chatName": firstChatName,
                            "message": "",
                            "taskType": "single",
                            "startDate": now.toISOString(),
                            "schedType": "days",
                            "schedEvery": 1,
                            "schedTime": "09:00",
                            "schedDays": [1],
                            "schedDayOfMonth": 1,
                            "limitEnabled": false,
                            "limitCount": 5,
                            "notify": true,
                            "createdAt": new Date().toISOString()
                        };
                        scheduleDialog.editingIndex = -2;
                    }
                }
            }

            // ── Archived Tab Header ──
            RowLayout {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "archived"

                QQC2.Label {
                    text: scheduleDialog.localArchivedList.length === 0 ? translate("No archived schedules") : (scheduleDialog.localArchivedList.length === 1 ? translate("1 archived schedule") : translate("%1 archived schedules").arg(scheduleDialog.localArchivedList.length))
                    opacity: 0.7
                    Layout.fillWidth: true
                }
            }

            // ── History Tab Header ──
            RowLayout {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "history"
                spacing: Kirigami.Units.mediumSpacing

                QQC2.Label {
                    text: page.schedulerHistory.length === 0 ? translate("No executed runs history") : (page.schedulerHistory.length === 1 ? translate("1 executed run logged") : translate("%1 executed runs logged").arg(page.schedulerHistory.length))
                    opacity: 0.7
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                QQC2.Button {
                    text: translate("Clear History")
                    icon.name: "edit-clear-all"
                    enabled: page.schedulerHistory.length > 0
                    onClicked: {
                        page.schedulerHistory = [];
                        page.schedSaveAll();
                    }
                }
            }

            // ── Empty State Inline Messages ──
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "active" && scheduleDialog.localActiveList.length === 0
                type: Kirigami.MessageType.Information
                text: translate("No active schedules configured yet. Click <b>New Schedule</b> to create one, or type <b>/schedule</b> in any chat.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "archived" && scheduleDialog.localArchivedList.length === 0
                type: Kirigami.MessageType.Information
                text: translate("No archived schedules. You can archive active schedules to temporarily pause them without losing their settings.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "history" && page.schedulerHistory.length === 0
                type: Kirigami.MessageType.Information
                text: translate("No history logs yet. Completed schedules and recurring run results will automatically appear here once triggered.")
            }

            // ── Scrollable Lists Area ──
            StackLayout {
                id: listStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: scheduleDialog.currentTab === "active" ? 0 : (scheduleDialog.currentTab === "archived" ? 1 : 2)

                // ── 1. ACTIVE SCHEDULES LIST ──
                ListView {
                    id: activeSchedListView
                    model: scheduleDialog.localActiveList
                    spacing: Kirigami.Units.smallSpacing
                    clip: true

                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        policy: QQC2.ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: activeSchedListView.width - 16
                        implicitHeight: activeSchedRow.implicitHeight + Kirigami.Units.smallSpacing * 3
                        radius: 6
                        color: modelData.enabled ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.07) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        border.width: 1
                        opacity: modelData.enabled ? 1 : 0.55

                        RowLayout {
                            id: activeSchedRow
                            spacing: Kirigami.Units.smallSpacing
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Kirigami.Units.smallSpacing * 1.5
                            }

                            QQC2.Switch {
                                checked: modelData.enabled
                                onToggled: {
                                    let copy = scheduleDialog.localActiveList.slice();
                                    let s = JSON.parse(JSON.stringify(copy[index]));
                                    s.enabled = checked;
                                    if (checked) {
                                        s.nextRunAt = "";
                                    }
                                    copy[index] = s;
                                    scheduleDialog.localActiveList = copy;
                                    scheduleDialog.saveAndSync();
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                QQC2.Label {
                                    text: modelData.name || modelData.humanReadable || translate("Unnamed")
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "⏱ " + (modelData.humanReadable || modelData.cron || "") + (modelData.chatName ? " · 💬 " + modelData.chatName : "")
                                    font.pixelSize: 11
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    visible: modelData.enabled && !!modelData.nextRunAt
                                    text: {
                                        if (!modelData.nextRunAt) return "";
                                        try {
                                            let clean = modelData.nextRunAt;
                                            if (clean.endsWith("Z")) {
                                                clean = clean.substring(0, clean.length - 1);
                                            }
                                            let dt = new Date(clean);
                                            return "➡ " + translate("Next run: %1").arg(dt.toLocaleString(Qt.locale(), Locale.ShortFormat));
                                        } catch (e) {
                                            return "➡ " + translate("Next run: %1").arg(modelData.nextRunAt);
                                        }
                                    }
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Kirigami.Theme.highlightColor
                                    opacity: 0.95
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    visible: modelData.taskType === "repeat" && modelData.limitEnabled
                                    text: "🔄 " + translate("Executed %1 of %2 times").arg(modelData.runCount || 0).arg(modelData.limitCount || 5)
                                    font.pixelSize: 10
                                    color: Kirigami.Theme.positiveTextColor
                                    opacity: 0.85
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "\"" + (modelData.message || "").substring(0, 60) + ((modelData.message || "").length > 60 ? "…" : "") + "\""
                                    font.pixelSize: 10
                                    opacity: 0.5
                                    elide: Text.ElideRight
                                    font.italic: true
                                    Layout.fillWidth: true
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "document-edit"
                                QQC2.ToolTip.text: translate("Edit")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    let d = JSON.parse(JSON.stringify(modelData));
                                    if (!d.taskType)
                                        d.taskType = "repeat";

                                    if (!d.startDate) {
                                        let now = new Date();
                                        now.setMinutes(now.getMinutes() + 5);
                                        now.setSeconds(0);
                                        now.setMilliseconds(0);
                                        d.startDate = now.toISOString();
                                    }
                                    if (!d.schedType)
                                        d.schedType = "days";

                                    if (!d.schedEvery)
                                        d.schedEvery = 1;

                                    if (!d.schedTime)
                                        d.schedTime = "09:00";

                                    if (!d.schedDays)
                                        d.schedDays = [1];

                                    if (!d.schedDayOfMonth)
                                        d.schedDayOfMonth = 1;

                                    scheduleDialog.draft = d;
                                    scheduleDialog.editingIndex = index;
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "archive-insert"
                                QQC2.ToolTip.text: translate("Archive")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    let copyActive = scheduleDialog.localActiveList.slice();
                                    let item = copyActive.splice(index, 1)[0];
                                    item.archived = true;

                                    let copyArchived = scheduleDialog.localArchivedList.slice();
                                    copyArchived.push(item);

                                    scheduleDialog.localActiveList = copyActive;
                                    scheduleDialog.localArchivedList = copyArchived;
                                    scheduleDialog.saveAndSync();
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                QQC2.ToolTip.text: translate("Remove")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    let copy = scheduleDialog.localActiveList.slice();
                                    copy.splice(index, 1);
                                    scheduleDialog.localActiveList = copy;
                                    scheduleDialog.saveAndSync();
                                }
                            }
                        }
                    }
                }

                // ── 2. ARCHIVED SCHEDULES LIST ──
                ListView {
                    id: archivedSchedListView
                    model: scheduleDialog.localArchivedList
                    spacing: Kirigami.Units.smallSpacing
                    clip: true

                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        policy: QQC2.ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: archivedSchedListView.width - 16
                        implicitHeight: archivedSchedRow.implicitHeight + Kirigami.Units.smallSpacing * 3
                        radius: 6
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        border.width: 1
                        opacity: 0.7

                        RowLayout {
                            id: archivedSchedRow
                            spacing: Kirigami.Units.smallSpacing
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Kirigami.Units.smallSpacing * 1.5
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                QQC2.Label {
                                    text: modelData.name || modelData.humanReadable || translate("Unnamed")
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "📁 " + (modelData.humanReadable || modelData.cron || "") + (modelData.chatName ? " · 💬 " + modelData.chatName : "")
                                    font.pixelSize: 11
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    visible: modelData.taskType === "repeat" && modelData.limitEnabled
                                    text: "🔄 " + translate("Executed %1 of %2 times").arg(modelData.runCount || 0).arg(modelData.limitCount || 5)
                                    font.pixelSize: 10
                                    color: Kirigami.Theme.positiveTextColor
                                    opacity: 0.85
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "\"" + (modelData.message || "").substring(0, 60) + ((modelData.message || "").length > 60 ? "…" : "") + "\""
                                    font.pixelSize: 10
                                    opacity: 0.5
                                    elide: Text.ElideRight
                                    font.italic: true
                                    Layout.fillWidth: true
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "archive-extract"
                                QQC2.ToolTip.text: translate("Restore to Active")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    let copyArchived = scheduleDialog.localArchivedList.slice();
                                    let item = copyArchived.splice(index, 1)[0];
                                    item.archived = false;
                                    item.nextRunAt = "";

                                    let copyActive = scheduleDialog.localActiveList.slice();
                                    copyActive.push(item);

                                    scheduleDialog.localActiveList = copyActive;
                                    scheduleDialog.localArchivedList = copyArchived;
                                    scheduleDialog.saveAndSync();
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                QQC2.ToolTip.text: translate("Delete Permanently")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    let copyArchived = scheduleDialog.localArchivedList.slice();
                                    copyArchived.splice(index, 1);
                                    scheduleDialog.localArchivedList = copyArchived;
                                    scheduleDialog.saveAndSync();
                                }
                            }
                        }
                    }
                }

                // ── 3. RUN HISTORY LIST ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    clip: true

                    ListView {
                        id: historySchedListView
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        model: page.schedulerHistory
                        spacing: Kirigami.Units.smallSpacing
                        clip: true

                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                            policy: QQC2.ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            width: historySchedListView.width - 16
                            implicitHeight: historyRowLayout.implicitHeight + Kirigami.Units.smallSpacing * 3
                            radius: 6
                            color: {
                                let isSuccess = modelData.status && modelData.status.indexOf("success") !== -1;
                                let base = isSuccess ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                                return Qt.rgba(base.r, base.g, base.b, 0.05);
                            }
                            border.color: {
                                let isSuccess = modelData.status && modelData.status.indexOf("success") !== -1;
                                let base = isSuccess ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                                return Qt.rgba(base.r, base.g, base.b, 0.15);
                            }
                            border.width: 1

                            RowLayout {
                                id: historyRowLayout
                                spacing: Kirigami.Units.smallSpacing
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Kirigami.Units.smallSpacing * 1.5

                                Kirigami.Icon {
                                    source: (modelData.status && modelData.status.indexOf("success") !== -1) ? "dialog-ok" : "dialog-error"
                                    color: (modelData.status && modelData.status.indexOf("success") !== -1) ? "#2ecc71" : "#e74c3c"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    QQC2.Label {
                                        text: modelData.scheduleName || translate("Unnamed Run")
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    QQC2.Label {
                                        text: "💬 " + (modelData.chatName || "Chat") + " · ⏱ " + modelData.timestamp
                                        font.pixelSize: 11
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    QQC2.Label {
                                        text: "\"" + (modelData.message || "") + "\""
                                        font.pixelSize: 10
                                        opacity: 0.6
                                        wrapMode: Text.Wrap
                                        font.italic: true
                                        Layout.fillWidth: true
                                    }

                                    QQC2.Label {
                                        text: translate("Status: ") + (modelData.status === "success" ? translate("Success") : (modelData.status === "error" ? translate("Failed") : modelData.status))
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: (modelData.status && modelData.status.indexOf("success") !== -1) ? "#27ae60" : "#c0392b"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }

            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                Layout.rightMargin: Kirigami.Units.gridUnit
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.mediumSpacing

                QQC2.Label {
                    text: "Note: " + translate("Configure schedules above. Click Save to apply changes, or Cancel to discard.")
                    font.pixelSize: 11
                    opacity: 0.65
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: translate("Close")
                    onClicked: {
                        scheduleDialog.close();
                    }
                }
            }

        }

        // ── Editor view ────────────────────────────────────────────────────────
        QQC2.ScrollView {
            anchors.fill: parent
            visible: scheduleDialog.editingIndex !== -1
            clip: true

            ColumnLayout {
                width: parent.width - Kirigami.Units.gridUnit
                spacing: Kirigami.Units.largeSpacing

                // Target Chat Selection
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Target Chat:")
                        font.bold: true
                    }

                    QQC2.ComboBox {
                        id: chatComboBox
                        Layout.fillWidth: true
                        textRole: "name"
                        model: scheduleDialog.getChatsList()

                        Component.onCompleted: {
                            syncIndex();
                        }

                        Connections {
                            target: scheduleDialog
                            function onDraftChanged() {
                                chatComboBox.syncIndex();
                            }
                        }

                        function syncIndex() {
                            let targetId = scheduleDialog.draft.chatId || "";
                            let currentModel = chatComboBox.model;
                            if (currentModel && currentModel.length) {
                                for (let i = 0; i < currentModel.length; i++) {
                                    if (currentModel[i] && currentModel[i].id === targetId) {
                                        chatComboBox.currentIndex = i;
                                        return;
                                    }
                                }
                            }
                            chatComboBox.currentIndex = 0;
                        }

                        onActivated: {
                            let selected = model[index];
                            if (selected && selected.id) {
                                scheduleDialog.updateDraft({
                                    "chatId": selected.id,
                                    "chatName": selected.name
                                });
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Message
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Message to send:")
                        font.bold: true
                    }

                    QQC2.Label {
                        text: translate("This message will be sent into the chat at the scheduled time, and the AI will reply.")
                        font.pixelSize: 11
                        opacity: 0.65
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    QQC2.TextArea {
                        id: dlgMessage

                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        maximumLength: 100000
                        wrapMode: TextEdit.Wrap
                        text: scheduleDialog.draft.message || ""
                        placeholderText: translate("e.g. What should I focus on today?")
                        onTextChanged: scheduleDialog.updateDraft({"message": text});}

                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Schedule builder
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Task Type:")
                        font.bold: true
                    }

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Button {
                            text: translate("Single Run")
                            highlighted: (scheduleDialog.draft.taskType || "single") === "single"
                            flat: (scheduleDialog.draft.taskType || "single") !== "single"
                            onClicked: {
                                scheduleDialog.updateDraft({"taskType": "single"});
                            }
                        }

                        QQC2.Button {
                            text: translate("Recurring (Repeatable)")
                            highlighted: (scheduleDialog.draft.taskType || "single") === "repeat"
                            flat: (scheduleDialog.draft.taskType || "single") !== "repeat"
                            onClicked: {
                                scheduleDialog.updateDraft({"taskType": "repeat"});
                            }
                        }

                    }

                }

                // ── Date and Time picker ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.mediumSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: (scheduleDialog.draft.taskType || "single") === "single" ? translate("Scheduled Date:") : translate("Start Date (Optional):")
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.ComboBox {
                                id: startMonthCombo

                                Layout.fillWidth: true
                                model: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"].map(function(x) { return translate(x); })
                                currentIndex: scheduleDialog.getStartMonth(scheduleDialog.draft.startDate)
                                onActivated: {
                                    scheduleDialog.setStartDateField("month", index);
                                }
                            }

                            QQC2.SpinBox {
                                id: startDaySpin

                                from: 1
                                to: 31
                                value: scheduleDialog.getStartDay(scheduleDialog.draft.startDate)
                                onValueModified: {
                                    scheduleDialog.setStartDateField("day", value);
                                }
                            }

                            QQC2.SpinBox {
                                id: startYearSpin

                                from: 2000
                                to: new Date().getFullYear() + 10
                                value: scheduleDialog.getStartYear(scheduleDialog.draft.startDate)
                                onValueModified: {
                                    scheduleDialog.setStartDateField("year", value);
                                }
                            }

                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Scheduled Time (Local):")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                id: startHourSpin

                                from: 0
                                to: 23
                                value: scheduleDialog.getStartHour(scheduleDialog.draft.startDate)
                                textFromValue: function(v) {
                                    return (v < 10 ? "0" : "") + v;
                                }
                                onValueModified: {
                                    scheduleDialog.setStartDateField("hour", value);
                                }
                            }

                            QQC2.Label {
                                text: ":"
                            }

                            QQC2.SpinBox {
                                id: startMinSpin

                                from: 0
                                to: 59
                                value: scheduleDialog.getStartMin(scheduleDialog.draft.startDate)
                                textFromValue: function(v) {
                                    return (v < 10 ? "0" : "") + v;
                                }
                                onValueModified: {
                                    scheduleDialog.setStartDateField("minute", value);
                                }
                            }

                        }

                    }

                }

                // ── Recurrence options ──
                ColumnLayout {
                    visible: (scheduleDialog.draft.taskType || "single") === "repeat"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Repeat Every:")
                            font.bold: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: [{
                                    "key": "minutes",
                                    "label": "Minutes"
                                }, {
                                    "key": "hours",
                                    "label": "Hours"
                                }, {
                                    "key": "days",
                                    "label": "Days"
                                }, {
                                    "key": "weeks",
                                    "label": "Weeks"
                                }, {
                                    "key": "months",
                                    "label": "Months"
                                }]

                                QQC2.Button {
                                    text: translate(modelData.label)
                                    flat: (scheduleDialog.draft.schedType || "days") !== modelData.key
                                    highlighted: (scheduleDialog.draft.schedType || "days") === modelData.key
                                    padding: Kirigami.Units.smallSpacing * 1.5
                                    font.pixelSize: 12
                                    onClicked: {
                                        scheduleDialog.updateDraft({"schedType": modelData.key});
                                    }}

                            }

                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Repeat Every:")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                id: dlgEvery

                                from: 1
                                to: 999
                                value: scheduleDialog.draft.schedEvery || 1
                                onValueModified: {
                                    scheduleDialog.updateDraft({"schedEvery": value});
                                }}

                            QQC2.Label {
                                text: {
                                    let t = scheduleDialog.draft.schedType || "days", n = scheduleDialog.draft.schedEvery || 1;
                                    let labels = {
                                        "minutes": "minute",
                                        "hours": "hour",
                                        "days": "day",
                                        "weeks": "week",
                                        "months": "month"
                                    };
                                    let base = labels[t] || t;
                                    return n === 1 ? translate(base) : translate(base + "s");
                                }
                            }

                        }

                    }


                    ColumnLayout {
                        visible: (scheduleDialog.draft.schedType || "") === "weeks"
                        spacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        QQC2.Label {
                            text: translate("On these days:")
                            font.bold: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

                                Rectangle {
                                    property bool sel: {
                                        let ds = scheduleDialog.draft.schedDays || [1];
                                        return ds.indexOf(index) >= 0;
                                    }

                                    width: 44
                                    height: 28
                                    radius: 5
                                    color: sel ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                    border.color: sel ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                    border.width: 1

                                    QQC2.Label {
                                        anchors.centerIn: parent
                                        text: translate(modelData)
                                        font.pixelSize: 11
                                        font.bold: sel
                                        color: sel ? "white" : Kirigami.Theme.textColor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            let ds = (scheduleDialog.draft.schedDays || [1]).slice();
                                            let pos = ds.indexOf(index);
                                            if (pos >= 0) {
                                                if (ds.length > 1)
                                                    ds.splice(pos, 1);
                                            } else {
                                                ds.push(index);
                                                ds.sort();
                                            }
                                            scheduleDialog.updateDraft({"schedDays": ds});
                                        }
                                    }

                                }

                            }

                        }

                    }

                    ColumnLayout {
                        visible: (scheduleDialog.draft.schedType || "") === "months"
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("On Day of Month:")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                from: 1
                                to: 28
                                value: scheduleDialog.draft.schedDayOfMonth || 1
                                onValueModified: {
                                    scheduleDialog.updateDraft({"schedDayOfMonth": value});
                                }}

                            QQC2.Label {
                                text: translate("of the month")
                                opacity: 0.7
                            }

                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Execution Limit:")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.mediumSpacing

                            QQC2.CheckBox {
                                id: limitCheckbox

                                text: translate("Limit number of runs")
                                checked: !!scheduleDialog.draft.limitEnabled
                                onCheckedChanged: {
                                    scheduleDialog.updateDraft({"limitEnabled": checked});
                                }}

                            QQC2.SpinBox {
                                id: limitSpin

                                visible: limitCheckbox.checked
                                from: 1
                                to: 9999
                                value: scheduleDialog.draft.limitCount || 5
                                onValueModified: {
                                    scheduleDialog.updateDraft({"limitCount": value});
                                }}

                            QQC2.Label {
                                visible: limitCheckbox.checked
                                text: translate("times")
                                opacity: 0.7
                            }

                        }

                    }

                }

                // Summary chip
                Rectangle {
                    Layout.fillWidth: true
                    height: dlgSummary.implicitHeight + Kirigami.Units.gridUnit
                    radius: 6
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
                    border.width: 1

                    QQC2.Label {
                        id: dlgSummary

                        text: "📅 " + scheduleDialog.humanText(scheduleDialog.draft)
                        font.bold: true
                        wrapMode: Text.Wrap
                        color: Kirigami.Theme.highlightColor

                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                            margins: Kirigami.Units.gridUnit * 0.6
                        }

                    }

                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Label (always on top)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Label (optional):")
                        font.bold: true
                    }

                    QQC2.TextField {
                        id: dlgName

                        Layout.fillWidth: true
                        text: scheduleDialog.draft.name || ""
                        placeholderText: translate("Leave blank to auto-name")
                        onTextChanged: scheduleDialog.updateDraft({"name": text});}

                }

                RowLayout {
                    QQC2.Switch {
                        id: dlgNotify

                        checked: scheduleDialog.draft.notify !== false
                        onCheckedChanged: {
                            scheduleDialog.updateDraft({"notify": checked});
                        }}

                    QQC2.Label {
                        text: dlgNotify.checked ? translate("Show a notification when the AI replies") : translate("Silent — no notification")
                        opacity: 0.75
                        wrapMode: Text.Wrap
                    }

                }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    QQC2.Button {
                        text: translate("Cancel")
                        onClicked: scheduleDialog.editingIndex = -1
                    }

                    QQC2.Button {
                        text: scheduleDialog.editingIndex === -2 ? translate("Create Schedule") : translate("Save Changes")
                        highlighted: true
                        enabled: dlgMessage.text.trim() !== ""
                        onClicked: {
                            let d = Object.assign({
                            }, scheduleDialog.draft);
                            d.cron = scheduleDialog.buildCron(d);
                            d.humanReadable = scheduleDialog.humanText(d);
                            if (!d.name || d.name.trim() === "")
                                d.name = d.humanReadable;
                            d.nextRunAt = "";

                            let copy = scheduleDialog.localActiveList.slice();
                            if (scheduleDialog.editingIndex === -2)
                                copy.push(d);
                            else
                                copy[scheduleDialog.editingIndex] = d;
                            scheduleDialog.localActiveList = copy;
                            scheduleDialog.saveAndSync();
                            scheduleDialog.editingIndex = -1;
                        }
                    }

                }

            }

        }

    }
