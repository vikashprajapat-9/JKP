// Activates or deactivates channel partner portal users in a transaction of their own (user changes cannot share one
// with changes to their accounts). A deactivated login no longer uses a licence. PartnerAccessRequestService reactivates
// the users of a partner whose access was extended after it was denied, and deactivates those of a terminated partner;
// the nightly PartnerExclusiveCheckBatch deactivates those of every Access Denied or Terminated partner. Executives go
// with their channel head. One user that cannot be changed does not stop the others.
public without sharing class PartnerUserActivationQueueable implements Queueable {

    private final Set<Id> userIds;
    private final Boolean active;

    public PartnerUserActivationQueueable(Set<Id> userIds, Boolean active) {
        this.userIds = userIds;
        this.active = active;
    }

    public void execute(QueueableContext context) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        Boolean wasActive = !active;
        List<User> changed = new List<User>();
        for (User partner : [SELECT Id FROM User WHERE Id IN :userIds AND IsActive = :wasActive WITH SYSTEM_MODE]) {
            changed.add(new User(Id = partner.Id, IsActive = active));
        }
        for (Database.SaveResult result : Database.update(changed, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Partner user not ' + (active ? 'activated' : 'deactivated') + ': ' + result.getErrors());
            }
        }
    }
}