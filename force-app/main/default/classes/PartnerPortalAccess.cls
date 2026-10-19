// Who the logged-in portal user is to the partner portal, and so what every portal page may show them.
// - A channel head (a channel partner account without a Channel Head) sees their own records and their executives'
//   (the channel partner accounts whose Channel Head is theirs), in every project.
// - An executive (a channel partner account with a Channel Head) sees only their own records, and only in the projects
//   their channel head gave them (their Project Access records).
// - A user without a partner account (an internal user previewing the site) has no records here, nor has a partner
//   who no longer has access (PartnerTemporaryAccess: temporary access ended without its conditions met, Access Denied,
//   Terminated), should they open the portal some other way than its login page.
// Without sharing: partners cannot read their executives' records or Project Access. The conditions below are what
// limit every query of the portal pages to what the partner may see.
public without sharing class PartnerPortalAccess {

    public final Id accountId;
    public final Boolean isExecutive;
    // The executive's projects; null for a channel head, who is not limited to some projects
    public final Set<Id> projectIds;

    // One per user in a transaction (tests switch users with System.runAs)
    private static final Map<Id, PartnerPortalAccess> BY_USER = new Map<Id, PartnerPortalAccess>();

    // The logged-in user's access
    public static PartnerPortalAccess current() {
        Id userId = UserInfo.getUserId();
        if (!BY_USER.containsKey(userId)) {
            User me = [
                SELECT ContactId, Contact.AccountId, Contact.Account.Id, Contact.Account.Partner_Type__c,
                    Contact.Account.Temporary_Access_Start_Date__c, Contact.Account.Temporary_Access_End_Date__c, Contact.Account.Channel_Head__c,
                    Contact.Account.Channel_Head__r.Id, Contact.Account.Channel_Head__r.Partner_Type__c,
                    Contact.Account.Channel_Head__r.Temporary_Access_Start_Date__c, Contact.Account.Channel_Head__r.Temporary_Access_End_Date__c
                FROM User WHERE Id = :userId WITH SYSTEM_MODE
            ];
            Boolean hasAccess = me.ContactId != null && me.Contact.AccountId != null && !PartnerTemporaryAccess.isDenied(me.Contact.Account);
            BY_USER.put(userId, hasAccess ? new PartnerPortalAccess(me.Contact.AccountId, me.Contact.Account.Channel_Head__c)
                : new PartnerPortalAccess(null, null));
        }
        return BY_USER.get(userId);
    }

    // The access of a channel partner account's users, for callers without their session (the login page and the
    // temporary access checks, PartnerTemporaryAccess)
    public static PartnerPortalAccess forAccount(Id partnerAccountId) {
        List<Account> accounts = partnerAccountId == null ? new List<Account>()
            : [SELECT Id, Channel_Head__c FROM Account WHERE Id = :partnerAccountId WITH SYSTEM_MODE];
        return accounts.isEmpty() ? new PartnerPortalAccess(null, null) : new PartnerPortalAccess(accounts[0].Id, accounts[0].Channel_Head__c);
    }

    private PartnerPortalAccess(Id partnerAccountId, Id channelHeadId) {
        accountId = partnerAccountId;
        isExecutive = accountId != null && channelHeadId != null;
        if (isExecutive) {
            Set<Id> projects = new Set<Id>();
            for (Project_Access__c access : [
                SELECT Project__c FROM Project_Access__c WHERE Account__c = :accountId AND Project__c != null WITH SYSTEM_MODE
            ]) {
                projects.add(access.Project__c);
            }
            projectIds = projects;
        } else {
            projectIds = null;
        }
    }

    // Whether the partner may see this project: an executive only the projects they were given
    public Boolean canSeeProject(Id projectId) {
        return projectId != null && (projectIds == null || projectIds.contains(projectId));
    }

    // The SOQL conditions below put their bind values (accessAccountId, accessProjectIds) in the given binds

    // A CP lead the managers rejected (a customer Direct Sales has) is not the partner's; one still waiting for their
    // approval is shown, but cannot be used yet (see LeadLogicController.prepareChannelPartnerLeads)
    // No records: the condition of a user without a partner account, or without access any more
    private static final String NOTHING = 'Id = null';

    private static final String NOT_REJECTED = 'CP_Approval_Status__c != \'Rejected\'';
    private static final String NOT_WAITING = 'CP_Approval_Status__c NOT IN (\'Pending\', \'Rejected\')';

    // The leads of the partner's team; an executive's own leads in their projects
    public String leads(Map<String, Object> binds) {
        putBinds(binds);
        if (accountId == null) {
            return NOTHING;
        }
        return isExecutive
            ? '(Channel_Partner__c = :accessAccountId AND Project__c IN :accessProjectIds AND ' + NOT_REJECTED + ')'
            : '((Channel_Partner__c = :accessAccountId OR Channel_Partner__r.Channel_Head__c = :accessAccountId) AND ' + NOT_REJECTED + ')';
    }

    // The partner's own leads that may be used (for a site visit), not their executives'; an executive's in their
    // projects. Not a lead whose customer went to another channel partner (the CP Lead Lost Status: another CP
    // completed the first successful site visit).
    public String ownLeads(Map<String, Object> binds) {
        putBinds(binds);
        if (accountId == null) {
            return NOTHING;
        }
        String usable = NOT_WAITING;
        Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');
        if (setting != null && String.isNotBlank(setting.CP_Lead_Lost_Status__c)) {
            binds.put('accessLostStatus', setting.CP_Lead_Lost_Status__c.trim());
            usable += ' AND Status != :accessLostStatus';
        }
        return isExecutive
            ? '(Channel_Partner__c = :accessAccountId AND Project__c IN :accessProjectIds AND ' + usable + ')'
            : '(Channel_Partner__c = :accessAccountId AND ' + usable + ')';
    }

    // The opportunities of the partner's team; an executive's own, in their projects or without a project (the
    // opportunity of a converted lead need not have one)
    public String opportunities(Map<String, Object> binds) {
        putBinds(binds);
        if (accountId == null) {
            return NOTHING;
        }
        return isExecutive
            ? '(Channel_Partner__c = :accessAccountId AND (Project__c = null OR Project__c IN :accessProjectIds))'
            : '(Channel_Partner__c = :accessAccountId OR Channel_Partner__r.Channel_Head__c = :accessAccountId)';
    }

    // The site visits of the partner's team, by the visit's or its lead's Channel Partner; an executive's own, in their
    // projects (the visit's project, else its lead's) or without a project
    public String visits(Map<String, Object> binds) {
        putBinds(binds);
        if (accountId == null) {
            return NOTHING;
        }
        if (!isExecutive) {
            return '(Channel_Partner__c = :accessAccountId OR Channel_Partner__r.Channel_Head__c = :accessAccountId'
                + ' OR Lead__r.Channel_Partner__c = :accessAccountId OR Lead__r.Channel_Partner__r.Channel_Head__c = :accessAccountId)';
        }
        return '((Channel_Partner__c = :accessAccountId OR Lead__r.Channel_Partner__c = :accessAccountId)'
            + ' AND (Project__c IN :accessProjectIds OR (Project__c = null AND (Lead__r.Project__c IN :accessProjectIds OR Lead__r.Project__c = null))))';
    }

    // The projects the partner may see, as a condition on Project__c (every project for a channel head)
    public String projects(Map<String, Object> binds) {
        putBinds(binds);
        return isExecutive ? 'Id IN :accessProjectIds' : 'Id != null';
    }

    private void putBinds(Map<String, Object> binds) {
        binds.put('accessAccountId', accountId);
        binds.put('accessProjectIds', projectIds == null ? new Set<Id>() : projectIds);
    }
}