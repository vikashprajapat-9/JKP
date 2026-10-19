public without sharing class CostSheetApprovalQueueable implements Queueable {
    private Set<Id> costSheetIds;
    private Integer approvalLevel;
    public CostSheetApprovalQueueable(Set<Id> costSheetIds,Integer approvalLevel) {
        this.costSheetIds = costSheetIds;
        this.approvalLevel = approvalLevel;
    }
    public void execute(QueueableContext context) {

        System.debug('========== COST SHEET APPROVAL QUEUEABLE ==========');
        System.debug('Cost Sheet IDs ==> ' + costSheetIds);
        System.debug('Approval Level ==> ' + approvalLevel);

        for (Id costSheetId : costSheetIds) {
            try {
                System.debug('Starting approval for Cost Sheet ==> ' + costSheetId );
                CostSheetGenerationController.processNextApproval(costSheetId,approvalLevel);
                System.debug('Approval Level ' + approvalLevel + ' submitted for Cost Sheet ==> ' + costSheetId);
            } catch (Exception e) {
                System.debug('ERROR submitting approval for Cost Sheet ' + costSheetId + ' ==> ' + e.getMessage());
                System.debug('ERROR LINE ==> ' +e.getLineNumber());
            }
        }
    }
}