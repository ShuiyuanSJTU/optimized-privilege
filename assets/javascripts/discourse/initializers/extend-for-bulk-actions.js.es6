import { withPluginApi } from "discourse/lib/plugin-api";
import { addBulkButton } from "discourse/controllers/topic-bulk-actions";

function initializeExtendBulkActions(api) {
  addBulkButton("openTopics", "open_topics", {
    icon: "unlock",
    class: "btn-default",
    buttonVisible: (topics) => topics.some((t) => t.closed),
  });
  addBulkButton("unarchiveTopics", "unarchive_topics", {
    icon: "folder",
    class: "btn-default",
    buttonVisible: (topics) => topics.some((t) => t.archived),
  });

  api.modifyClass("controller:topic-bulk-actions", {
    pluginId: "extend-for-bulk-actions",
    actions: {
      openTopics() {
        this.forEachPerformed({ type: "open" }, (t) => t.set("closed", false));
      },

      unarchiveTopics() {
        this.forEachPerformed({ type: "unarchive" }, (t) =>
          t.set("archived", false)
        );
      },
    },
  });
}

export default {
  name: "extend-for-bulk-actions",
  initialize() {
    withPluginApi("0.8.28", initializeExtendBulkActions);
  },
};
