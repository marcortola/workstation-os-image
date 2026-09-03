import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// The open herdr spaces on the bar: a pill counting the ones that want an
// answer, and a popout listing them exactly as the space picker does.
//
// Every row comes from `spaces.sh --json`, the same builder the picker renders
// as padded TSV. Nothing about state, the just-finished mark or the attention
// order is recomputed here on purpose: two views of one list that disagree is
// what the shared builder exists to prevent, and herdr times nothing, so the
// freshness mark can only come from the stamp the plugin's hook writes.
PluginComponent {
    id: root

    layerNamespacePlugin: "herdrJobs"

    readonly property string devFlow: "\"$HOME\"/.config/herdr/plugins/dev-flow"

    property var rows: []
    property bool serverUp: false
    // A poll still in flight is skipped rather than queued: with herdr wedged,
    // a 3s timer against a 10s command timeout would otherwise stack processes.
    property bool polling: false

    // blocked and done are attention_rank 0 in spaces.sh, the rows it floats to
    // the top. They are the two ways a space wants a human: one agent is asking
    // a question, the other has finished and wants a review.
    //
    // The pill carries no numbers. How many are waiting does not change what you
    // do next -- you open the popout either way -- so the bar answers only which
    // of three things is true: someone is waiting on you, something is running,
    // or neither.
    //
    // done rather than the picker's `*` mark: herdr keeps saying done until the
    // space goes back to work, so the signal survives until it is dealt with,
    // where the mark expires after AGENT_FRESH_SECONDS whether or not anyone
    // looked.
    readonly property int blockedCount: rows.filter(r => r.state === "blocked").length
    readonly property int doneCount: rows.filter(r => r.state === "done").length
    readonly property int workingCount: rows.filter(r => r.state === "working").length
    // parked is a turn that ended leaving background work running. herdr calls
    // that pane idle and is not wrong about the turn; the bar answers about the
    // work, so it counts beside working and shares its colour.
    readonly property int parkedCount: rows.filter(r => r.state === "parked").length

    // The picker's colours, in the picker's vocabulary: red wants an answer,
    // green finished, yellow is still going, dim is neither.
    function stateColor(state) {
        switch (state) {
        case "blocked":
            return Theme.error;
        case "done":
            return Theme.success;
        case "working":
        case "parked":
            return Theme.warning;
        default:
            return Theme.surfaceVariantText;
        }
    }

    function refresh() {
        if (root.polling)
            return;
        root.polling = true;
        Proc.runCommand("herdrJobs.rows", ["sh", "-c", "exec " + root.devFlow + "/spaces.sh --json"], (stdout, exitCode) => {
            root.polling = false;
            // spaces.sh exits non-zero with no server, which is how "no spaces"
            // stays distinguishable from "herdr is not running".
            if (exitCode !== 0) {
                root.serverUp = false;
                root.rows = [];
                return;
            }
            try {
                root.rows = JSON.parse(stdout);
                root.serverUp = true;
            } catch (e) {
                root.serverUp = false;
                root.rows = [];
            }
        }, 0);
    }

    // Scoping the session is only half of it from out here: the client is in a
    // window this popout is not, so focus-space.sh raises it too.
    function focusSpace(workspaceId) {
        Quickshell.execDetached(["sh", "-c", "exec " + root.devFlow + "/focus-space.sh \"$1\"", "sh", workspaceId]);
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // The icon takes the most urgent colour present, in the picker's vocabulary:
    // red wants an answer, green finished, yellow is still going, plain is idle.
    readonly property color pillColor: blockedCount > 0 ? Theme.error : (doneCount > 0 ? Theme.success : ((workingCount + parkedCount) > 0 ? Theme.warning : Theme.surfaceText))

    // The glyph never changes -- the widget is the robot, and a shape that moves
    // is a second thing to learn. Working rides on top of it instead, as a dot
    // in the corner, so it survives the colour being spent on blocked or done:
    // "someone is waiting on you AND something is still running" is one look.
    readonly property bool showWorkingDot: (workingCount + parkedCount) > 0

    horizontalBarPill: Component {
        Item {
            implicitWidth: horizontalPillIcon.implicitWidth
            implicitHeight: horizontalPillIcon.implicitHeight

            DankIcon {
                id: horizontalPillIcon
                anchors.centerIn: parent
                name: "smart_toy"
                size: root.iconSize
                color: root.serverUp ? root.pillColor : Theme.surfaceText
                opacity: root.serverUp ? 1 : 0.4
            }

            // Ringed in the bar's own background so the dot stays a dot against
            // whichever part of the glyph it lands on.
            Rectangle {
                visible: root.serverUp && root.showWorkingDot
                width: Math.round(root.iconSize * 0.42)
                height: width
                radius: width / 2
                color: Theme.surfaceContainer
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.66
                    height: width
                    radius: width / 2
                    color: Theme.warning
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: verticalPillIcon.implicitWidth
            implicitHeight: verticalPillIcon.implicitHeight

            DankIcon {
                id: verticalPillIcon
                anchors.centerIn: parent
                name: "smart_toy"
                size: root.iconSize
                color: root.serverUp ? root.pillColor : Theme.surfaceText
                opacity: root.serverUp ? 1 : 0.4
            }

            // Ringed in the bar's own background so the dot stays a dot against
            // whichever part of the glyph it lands on.
            Rectangle {
                visible: root.serverUp && root.showWorkingDot
                width: Math.round(root.iconSize * 0.42)
                height: width
                radius: width / 2
                color: Theme.surfaceContainer
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.66
                    height: width
                    radius: width / 2
                    color: Theme.warning
                }
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 440

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "herdr spaces"
            detailsText: root.serverUp ? (root.rows.length + " open, " + root.blockedCount + " blocked, " + root.doneCount + " done, " + root.workingCount + " working, " + root.parkedCount + " parked") : "herdr is not running"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.rows.length === 0
                    text: root.serverUp ? "No open spaces." : "Start herdr with Mod+Shift+T."
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }

                DankListView {
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    visible: root.rows.length > 0
                    model: root.rows

                    delegate: StyledRect {
                        width: ListView.view.width
                        height: 30
                        radius: Theme.cornerRadiusSmall
                        color: rowArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                        border.width: 0

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            // Fixed width so the states line up into a column the
                            // way they do in the picker.
                            StyledText {
                                width: 62
                                text: modelData.marked_state
                                color: root.stateColor(modelData.state)
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                leftPadding: modelData.is_worktree ? Theme.spacingM : 0
                                text: (modelData.is_worktree ? "└ " : "") + modelData.label
                                color: modelData.is_worktree ? Theme.surfaceVariantText : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.focusSpace(modelData.workspace_id);
                                popout.closePopout();
                            }
                        }
                    }
                }
            }
        }
    }
}
