/* Author      : Nazir_Patel / Antigravity
   Description : Controller for DOA Customer Payment Communication Proof Upload LWC.
                 Closes the upload task and triggers the Financial Approval Process.
*/
public without sharing class DoaProofUploadController {

    @AuraEnabled
    public static void updateTask(Id recordId) {
        try {
            if (recordId == null) {
                AuraHandledException e = new AuraHandledException('Record ID was not found or passed to the component.');
                e.setMessage('Record ID was not found or passed to the component.');
                throw e;
            }

            Id caseId = null;
            String recordIdStr = String.valueOf(recordId);

            // 1. If called from a Task (00T...) — normal path
            if (recordIdStr.startsWith('00T')) {
                Task t = [
                    SELECT Id, Status, WhatId, Subject 
                    FROM Task 
                    WHERE Id = :recordId 
                    LIMIT 1
                ];
                
                // Mark task as Completed so it closes cleanly
                t.Status = 'Completed';
                update as system t;

                if (t.WhatId != null && String.valueOf(t.WhatId).startsWith('500')) {
                    caseId = t.WhatId;
                }
            } 
            // 2. If called from Case record page (500...) — fallback path
            else if (recordIdStr.startsWith('500')) {
                caseId = recordId;

                List<Task> openProofTasks = [
                    SELECT Id, Status 
                    FROM Task 
                    WHERE WhatId = :caseId 
                      AND Subject LIKE '%Upload Customer Proof%' 
                      AND Status != 'Closed' 
                      AND Status != 'Completed'
                ];
                for (Task t : openProofTasks) {
                    t.Status = 'Completed';
                }
                if (!openProofTasks.isEmpty()) {
                    update as system openProofTasks;
                }
            }

            // 3. Fire Approval on the Parent Case
            //    CaseDOAHandler.submitForApproval has its own duplicate guard via processedApprovalCaseIds
            if (caseId != null) {
                CaseDOAHandler.submitForApproval(
                    caseId, 
                    'Customer payment communication proof uploaded by Customer Service.'
                );
            }

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            System.debug('Error in DoaProofUploadController.updateTask: ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());
            ahe.setMessage(ex.getMessage());
            throw ahe;
        }
    }
}