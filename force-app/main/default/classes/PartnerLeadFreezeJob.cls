// Nightly Lead Freezing Window check (PartnerLeadFreeze): channel partner leads whose Freezing Date has come without a
// site visit done move to the Partnership Queue, and their partners are emailed. Schedule it as an administrator.
public without sharing class PartnerLeadFreezeJob implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext context) {
        Database.executeBatch(new PartnerLeadFreezeJob(), 100);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return PartnerLeadFreeze.dueLeads();
    }

    public void execute(Database.BatchableContext context, List<Lead> scope) {
        PartnerLeadFreeze.freeze(scope);
    }

    public void finish(Database.BatchableContext context) {
    }
}