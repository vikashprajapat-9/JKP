({
    doInit : function(component, event, helper) {

        var recordId = component.get("v.recordId");

        if (!recordId) {
            component.set("v.isLoading", false);
            component.set(
                "v.statusMessage",
                "Unable to determine the current Task record."
            );
            return;
        }

        var action = component.get("c.getCurrentTaskRecord");

        action.setParams({
            recordId: recordId
        });

        action.setCallback(this, function(response) {
            component.set("v.isLoading", false);
            var state = response.getState();
            if (state === "SUCCESS") {
                var taskRecord = response.getReturnValue();
                /*
                 * Apex returns null when:
                 * - recordId is blank
                 * - Task doesn't have an active Task Master
                 * - Task cannot be retrieved
                 */
                if (!taskRecord) {
                    component.set(
                        "v.statusMessage",
                        "Your Task is not associated with any active Task Master record."
                    );
                    return;
                }
                /*
                 * Completed Tasks cannot open the configured action.
                 */
                if (taskRecord.Status === "Completed") {
                    component.set("v.statusMessage", "This Task is already marked as Completed. No further action can be performed.");
                    return;
                }

                /*
                 * Determine the parent record.
                 * Priority:
                 * 1. WhatId
                 * 2. WhoId
                 */
                var parentId = taskRecord.WhatId
                    ? taskRecord.WhatId
                    : taskRecord.WhoId
                        ? taskRecord.WhoId
                        : null;
                if (!parentId) {
                    component.set("v.statusMessage", "This Task is not associated with a parent record.");
                    return;
                }
                var taskMaster = taskRecord.Task_Master__r;
                if (!taskMaster) {
                    component.set("v.statusMessage", "Your Task is not associated with a valid Task Master record.");
                    return;
                }
                var actionType = taskMaster.Action_Type__c;
                var actionUrl = taskMaster.Action_URL__c;
                if (!actionType || !actionUrl) {
                    component.set("v.statusMessage", "No action has been configured for this Task.");
                    return;
                }
                component.set("v.actionType", actionType);

                /*
                 * ============================
                 * FLOW
                 * ============================
                 */
                if (actionType === "Flow") {
                    var inputVariables = [
                        {
                            name: "recordId",
                            type: "String",
                            value: parentId
                        }
                    ];
                    var flow = component.find("OnOpenStatus");
                    if (!flow) {
                        component.set("v.statusMessage", "Unable to initialize the configured Flow.");
                        return;
                    }
                    flow.startFlow(actionUrl, inputVariables);
                    return;
                }

                /*
                 * ============================
                 * DYNAMIC LWC
                 * ============================
                 */
                if (actionType === "Component") {
                    var componentName = "c:" + actionUrl;
                    $A.createComponent(
                        componentName,
                        {
                            recordId: parentId,
                           // recordId: taskRecord.Id,

                            /*
                             * The dynamically created LWC can dispatch
                             * a "close" event.
                             */
                            onclose: component.getReference("c.handleClose")
                        },

                        function(lwcCmp, status, errorMessage) {
                            if (status === "SUCCESS") {
                                component.set("v.body", [lwcCmp]);
                            } else if (status === "INCOMPLETE") {
                                console.error("Dynamic component creation incomplete.");
                                component.set("v.statusMessage", "Unable to load the requested component.");
                            } else if (status === "ERROR") {
                                console.error("Dynamic component creation error: " + errorMessage);
                                component.set("v.statusMessage", "Unable to load the requested component.");
                            }
                        }
                    );
                    return;
                }

                /*
                 * ============================
                 * INVALID ACTION TYPE
                 * ============================
                 */
                component.set("v.statusMessage", "The configured Task action type is not supported.");
            } else if (state === "ERROR") {
                var errors = response.getError();
                var errorMessage = "Unable to retrieve the Task configuration.";
                if (errors && errors.length > 0 && errors[0].message) {
                    errorMessage = errors[0].message;
                }
                console.error("Dynamic Task error:", errors);
                component.set("v.statusMessage", errorMessage);
            } else {
                component.set("v.statusMessage", "Unable to retrieve the Task configuration.");
            }
        });
        $A.enqueueAction(action);
    },

    handleClose : function(component, event, helper) {
        $A.get("e.force:closeQuickAction").fire();
    }
})