public class ParnterUserDeactivationQueueable implements Queueable {
    private Set<Id> userIds;

    public ParnterUserDeactivationQueueable(Set<Id> userIds) {
        this.userIds = userIds;
    }

    public void execute(QueueableContext context) {
        if (userIds == null || userIds.isEmpty()) return;

        List<User> usersToDeactivate = [
            SELECT Id, IsActive 
            FROM User 
            WHERE Id IN :userIds AND IsActive = true
        ];

        for (User u : usersToDeactivate) {
            u.IsActive = false;
        }

        if (!usersToDeactivate.isEmpty()) {
            update usersToDeactivate;
            System.debug('UserDeactivation Deactivated Users:=> ' + usersToDeactivate.size());
        }
    }
}