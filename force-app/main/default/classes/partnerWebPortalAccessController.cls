// The access banner of the partner portal: a channel head on temporary access is told, in the last days of it (Partner
// Portal Setting: Extension Offer Days), when it ends, and may request an extension (PartnerAccessRequestService), which
// the CP Manager approves. While a request waits, the banner says so. Executives go by their channel head and see
// nothing; a partner whose conditions are already met (its contract is coming) is not offered one either.
public without sharing class partnerWebPortalAccessController {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_ACCESS_ENDING = 'Your temporary access to the Partner Portal ends on {0} ({1} days left). Need more time? Request an extension.';
    @TestVisible private static final String PARTNER_ACCESS_EXTENSION_HEAD_ONLY = 'Only your channel partner can request an extension of the access.';
    @TestVisible private static final String PARTNER_ACCESS_EXTENSION_NOT_AVAILABLE = 'An extension cannot be requested for this login. Please contact the JKP CP team.';
    @TestVisible private static final String PARTNER_ACCESS_EXTENSION_PENDING = 'Your request for {0} more days of access, sent on {1}, is waiting for approval by John Keells Properties.';
    @TestVisible private static final String PARTNER_ACCESS_REQUEST_PENDING = 'A request of this kind is already waiting for approval.';


    public class AccessStatus {
        @AuraEnabled public Boolean isHead = false;
        @AuraEnabled public String partnerType;
        @AuraEnabled public String accessEnd;
        @AuraEnabled public Integer daysLeft;
        @AuraEnabled public Boolean canRequest = false;
        @AuraEnabled public Boolean pending = false;
        @AuraEnabled public Integer pendingDays;
        @AuraEnabled public String pendingSince;
        @AuraEnabled public List<Integer> options = new List<Integer>();
        @AuraEnabled public String message;
    }

    private static final String LOAD_ERROR = 'Your access details could not be loaded right now. Please try again.';

    @AuraEnabled
    public static AccessStatus getAccessStatus() {
        try {
            return statusOf(PartnerPortalAccess.current());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Access status failed: ' + e.getMessage());
            throw userError(LOAD_ERROR);
        }
    }

    @AuraEnabled
    public static AccessStatus requestExtension(Integer days, String reason) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null || access.isExecutive) {
            throw userError(PARTNER_ACCESS_EXTENSION_HEAD_ONLY);
        }
        AccessStatus status = statusOf(access);
        if (!status.canRequest) {
            throw userError(status.pending ? PARTNER_ACCESS_REQUEST_PENDING : PARTNER_ACCESS_EXTENSION_NOT_AVAILABLE);
        }
        try {
            PartnerAccessRequestService.requestExtension(access.accountId, days, reason, PartnerAccessRequestService.VIA_PORTAL, UserInfo.getUserId());
        } catch (PartnerAccessRequestService.RequestException e) {
            throw userError(e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Extension request failed: ' + e.getMessage());
            throw userError(PARTNER_ACCESS_EXTENSION_NOT_AVAILABLE);
        }
        return statusOf(access);
    }

    private static AccessStatus statusOf(PartnerPortalAccess access) {
        AccessStatus status = new AccessStatus();
        status.options = PartnerAccessRequestService.extensionOptions();
        if (access.accountId == null || access.isExecutive) {
            return status;
        }
        status.isHead = true;
        Account partner = [
            SELECT Id, Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c, Channel_Head__c
            FROM Account WHERE Id = :access.accountId WITH SYSTEM_MODE
        ];
        status.partnerType = partner.Partner_Type__c;
        Date endsOn = partner.Temporary_Access_End_Date__c;
        if (partner.Partner_Type__c != PartnerTemporaryAccess.TEMPORARY || endsOn == null) {
            return status;
        }
        status.accessEnd = formatted(endsOn);
        status.daysLeft = Math.max(0, PartnerTemporaryAccess.today().daysBetween(endsOn));
        Partner_Access_Request__c pending = PartnerAccessRequestService.pendingRequest(partner.Id, PartnerAccessRequestService.EXTENSION);
        if (pending != null) {
            status.pending = true;
            status.pendingDays = pending.Extension_Days__c == null ? null : pending.Extension_Days__c.intValue();
            status.pendingSince = formatted(pending.CreatedDate.date());
            status.message = String.format(PARTNER_ACCESS_EXTENSION_PENDING, new List<Object>{
                String.valueOf(status.pendingDays), status.pendingSince
            });
            return status;
        }
        if (status.daysLeft <= PartnerAccessRequestService.offerDays() && !status.options.isEmpty()
                && !PartnerTemporaryAccess.metConditions(partner)) {
            status.canRequest = true;
            status.message = String.format(PARTNER_ACCESS_ENDING, new List<Object>{ status.accessEnd, String.valueOf(status.daysLeft) });
        }
        return status;
    }

    private static String formatted(Date day) {
        return day == null ? null : Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0)).format('dd MMM yyyy');
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}