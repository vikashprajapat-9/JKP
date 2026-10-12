// The temporary access a channel partner gets when JKP approves them: Partner Type Temporary, with start and end dates
// (30 days, PartnerPortalUserCreation). Per the onboarding chart, "Condition met in 30 days? No: Access denied". Once the
// end date has passed, the partner may only keep logging in when, between the start and end dates, enough of their leads
// converted to customers, or enough site visits took place on leads created in that time. The numbers and the visit
// status that counts are in the Partner Portal Setting (Exclusive Converted Leads, Exclusive Site Visits, Completed
// Visit Status). The agent of the chart is the channel head: their leads and visits include their executives'
// (PartnerPortalAccess), and an executive has access exactly while their channel head does. Access Denied and
// Terminated accounts have no access. The portal login (partnerPortalLoginController), every portal page
// (PartnerPortalAccess.current) and the nightly PartnerExclusiveCheckBatch all decide with this class. Dates are those of
// the org's time zone, whoever runs it (the login runs as the site's guest user).
public without sharing class PartnerTemporaryAccess {

    public static final String TEMPORARY = 'Temporary';
    public static final String EXCLUSIVE = 'Exclusive';
    public static final String ACCESS_DENIED = 'Access Denied';
    public static final String TERMINATED = 'Terminated';

    // Before any temporary access: a partner without a start date is judged on everything up to the end date
    private static final Date EARLIEST = Date.newInstance(1900, 1, 1);

    @TestVisible
    private static Partner_Portal_Setting__mdt setting {
        get {
            if (setting == null) {
                setting = Partner_Portal_Setting__mdt.getInstance('Default');
            }
            return setting;
        }
        set;
    }

    private static TimeZone orgZone {
        get {
            if (orgZone == null) {
                orgZone = TimeZone.getTimeZone([SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey);
            }
            return orgZone;
        }
        set;
    }

    // Today in the org's time zone
    public static Date today() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', orgZone.getID()));
    }

    // Whether the partner may no longer use the portal: the account, or an executive's channel head, is Access Denied or
    // Terminated, or the (channel head's) temporary access has ended without the conditions being met. The account needs
    // Id, Partner_Type__c, the temporary access dates and Channel_Head__c, and for an executive the same of Channel_Head__r.
    public static Boolean isDenied(Account partner) {
        if (partner == null) {
            return false;
        }
        if (isClosed(partner.Partner_Type__c)) {
            return true;
        }
        if (partner.Channel_Head__c != null) {
            Account head = partner.Channel_Head__r;
            return head != null && (isClosed(head.Partner_Type__c) || (hasEnded(head) && !metConditions(head)));
        }
        return hasEnded(partner) && !metConditions(partner);
    }

    // Whether the account, or an executive's channel head, is Terminated
    public static Boolean isTerminated(Account partner) {
        return partner != null && (partner.Partner_Type__c == TERMINATED
            || (partner.Channel_Head__c != null && partner.Channel_Head__r != null && partner.Channel_Head__r.Partner_Type__c == TERMINATED));
    }

    public static Boolean isClosed(String partnerType) {
        return partnerType == ACCESS_DENIED || partnerType == TERMINATED;
    }

    // Temporary access whose end date has passed
    public static Boolean hasEnded(Account partner) {
        return partner.Partner_Type__c == TEMPORARY && partner.Temporary_Access_End_Date__c != null
            && partner.Temporary_Access_End_Date__c < today();
    }

    // Whether, between the start and end dates of the temporary access (up to today while it lasts), enough of the
    // partner's leads converted or enough completed site visits took place on leads created in that time
    public static Boolean metConditions(Account partner) {
        Partner_Portal_Setting__mdt rules = setting;
        if (rules == null || partner == null || partner.Id == null) {
            return false;
        }
        PartnerPortalAccess access = PartnerPortalAccess.forAccount(partner.Id);
        if (access.accountId == null) {
            return false;
        }
        Date first = partner.Temporary_Access_Start_Date__c == null ? EARLIEST : partner.Temporary_Access_Start_Date__c;
        Date last = partner.Temporary_Access_End_Date__c == null || partner.Temporary_Access_End_Date__c > today()
            ? today() : partner.Temporary_Access_End_Date__c;
        Set<Id> team = teamUsers(partner.Id);

        Integer conversionsNeeded = needed(rules.Exclusive_Converted_Leads__c);
        if (conversionsNeeded > 0 && conversions(access, team, first, last) >= conversionsNeeded) {
            return true;
        }
        Integer visitsNeeded = needed(rules.Exclusive_Site_Visits__c);
        return visitsNeeded > 0 && String.isNotBlank(rules.Completed_Visit_Status__c)
            && completedVisits(access, team, rules.Completed_Visit_Status__c.trim(), first, last) >= visitsNeeded;
    }

    // Whether the Partner Portal Setting has a condition at all (without one, nobody would ever meet them)
    public static Boolean hasConditions() {
        return setting != null && (needed(setting.Exclusive_Converted_Leads__c) > 0
            || (needed(setting.Exclusive_Site_Visits__c) > 0 && String.isNotBlank(setting.Completed_Visit_Status__c)));
    }

    // Days after the end of the temporary access before the nightly check marks the partner Access Denied
    public static Integer denialGraceDays() {
        return setting == null || setting.Denial_Grace_Days__c == null ? 0 : Math.max(0, setting.Denial_Grace_Days__c.intValue());
    }

    private static Integer needed(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    // The portal users of the channel head and of their executives: leads they created on the portal before leads got
    // their Channel Partner count by their owner
    private static Set<Id> teamUsers(Id headId) {
        return new Map<Id, User>([
            SELECT Id FROM User WHERE ContactId != null AND (Contact.AccountId = :headId OR Contact.Account.Channel_Head__c = :headId)
            WITH SYSTEM_MODE
        ]).keySet();
    }

    // The team's leads converted in the period
    private static Integer conversions(PartnerPortalAccess access, Set<Id> team, Date first, Date last) {
        Map<String, Object> binds = new Map<String, Object>{ 'periodFirst' => first, 'periodLast' => last, 'teamUsers' => team };
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM Lead WHERE (' + access.leads(binds) + ' OR (Channel_Partner__c = null AND OwnerId IN :teamUsers))'
                + ' AND IsConverted = true AND ConvertedDate >= :periodFirst AND ConvertedDate <= :periodLast',
            binds, AccessLevel.SYSTEM_MODE);
    }

    // The team's site visits with the completed status, on leads created in the period (and not rejected), that took
    // place in it: when they were completed, or else on their visit date, or else when they were recorded
    private static Integer completedVisits(PartnerPortalAccess access, Set<Id> team, String status, Date first, Date last) {
        Map<String, Object> binds = new Map<String, Object>{
            'visitStatus' => status,
            'periodFirst' => first,
            'periodLast' => last,
            'periodStart' => startOf(first),
            'periodEnd' => startOf(last.addDays(1)),
            'teamUsers' => team,
            'rejected' => 'Rejected'
        };
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM Visit__c WHERE (' + access.visits(binds)
                + ' OR (Lead__r.Channel_Partner__c = null AND Lead__r.OwnerId IN :teamUsers))'
                + ' AND Status__c = :visitStatus AND Lead__r.CP_Approval_Status__c != :rejected'
                + ' AND Lead__r.CreatedDate >= :periodStart AND Lead__r.CreatedDate < :periodEnd'
                + ' AND ((Completed_At_Date_Time__c >= :periodStart AND Completed_At_Date_Time__c < :periodEnd)'
                + ' OR (Completed_At_Date_Time__c = null AND Visit_Date__c >= :periodFirst AND Visit_Date__c <= :periodLast)'
                + ' OR (Completed_At_Date_Time__c = null AND Visit_Date__c = null AND CreatedDate >= :periodStart AND CreatedDate < :periodEnd))',
            binds, AccessLevel.SYSTEM_MODE);
    }

    // The start of the day in the org's time zone
    private static Datetime startOf(Date day) {
        Datetime midnightGmt = Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0));
        return midnightGmt.addSeconds(-orgZone.getOffset(midnightGmt) / 1000);
    }
}