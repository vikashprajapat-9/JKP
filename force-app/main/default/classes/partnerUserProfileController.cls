// user detail information are in this class
// The Profile page of the partner portal: the logged-in user's own details and those of their partner account. It
// reads only the running user's own record, in system mode, so the partner needs no field access to show it.
public without sharing class partnerUserProfileController {

    public class UserProfileWrapper {
        @AuraEnabled public String name             { get; set; }
        @AuraEnabled public String initials         { get; set; }
        @AuraEnabled public String email            { get; set; }
        @AuraEnabled public String mobile           { get; set; }
        @AuraEnabled public String companyName      { get; set; }
        @AuraEnabled public String partnerType      { get; set; }
        @AuraEnabled public String expiryDate       { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static UserProfileWrapper getUserProfile() {
        User u = [
            SELECT Name, Email, MobilePhone, Phone, ContactId, Contact.AccountId, Contact.Account.Name,
                   toLabel(Contact.Account.Partner_Type__c), Contact.Account.Temporary_Access_End_Date__c,
                   Contact.Account.Channel_Head__c, toLabel(Contact.Account.Channel_Head__r.Partner_Type__c),
                   Contact.Account.Channel_Head__r.Temporary_Access_End_Date__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        UserProfileWrapper profile = new UserProfileWrapper();
        profile.name = u.Name;
        profile.initials = initialsOf(u.Name);
        profile.email = String.isNotBlank(u.Email) ? u.Email : '-';
        profile.mobile = String.isNotBlank(u.MobilePhone) ? u.MobilePhone : (String.isNotBlank(u.Phone) ? u.Phone : '-');

        // The partner account's name and Partner Type; nothing for a user without one (an internal user previewing the site)
        Account partner = u.ContactId == null || u.Contact.AccountId == null ? null : u.Contact.Account;
        profile.companyName = partner == null ? null : partner.Name;
        // An executive works under their channel head's partner type, temporary access and contract
        Account agent = partner == null ? null : (partner.Channel_Head__c != null && partner.Channel_Head__r != null ? partner.Channel_Head__r : partner);
        Id agentId = partner == null ? null : (partner.Channel_Head__c != null ? partner.Channel_Head__c : u.Contact.AccountId);
        profile.partnerType = agent == null || String.isBlank(agent.Partner_Type__c) ? null : agent.Partner_Type__c;
        // The end date of the signed agent contract once it is on record, else the end of the temporary access;
        // formatted as DD-MM-YYYY
        Date expiry = agent == null ? null : agent.Temporary_Access_End_Date__c;
        if (agentId != null) {
            for (Contract signed : [
                SELECT Contract_End__c FROM Contract
                WHERE AccountId = :agentId AND Contract_Stage__c = 'Completed' AND Contract_End__c != null
                WITH SYSTEM_MODE ORDER BY Contract_End__c DESC LIMIT 1
            ]) {
                expiry = signed.Contract_End__c;
            }
        }
        profile.expiryDate = expiry == null ? '-' : Datetime.newInstance(expiry, Time.newInstance(0, 0, 0, 0)).format('dd-MM-yyyy');
        return profile;
    }

    // The first letters of the first two words, as the portal's top bar shows the logged-in user
    private static String initialsOf(String name) {
        String initials = '';
        if (String.isNotBlank(name)) {
            for (String word : name.trim().split('\\s+')) {
                if (initials.length() == 2) {
                    break;
                }
                initials += word.left(1);
            }
        }
        return initials.toUpperCase();
    }
}