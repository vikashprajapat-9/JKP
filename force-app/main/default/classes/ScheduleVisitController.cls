public with sharing class ScheduleVisitController {

    @AuraEnabled
    public static Id createVisit(Id leadId,Id opportunityId,Id projectId,String requirementType,Date visitDate,String visitTime,String remarks) {
        if (projectId == null) {
            throw new AuraHandledException('Project is required.');
        }

        if (String.isBlank(requirementType)) {
            throw new AuraHandledException('Requirement Type is required.');
        }

        if (visitDate == null) {
            throw new AuraHandledException('Visit Date is required.');
        }

        if (String.isBlank(visitTime)) {
            throw new AuraHandledException('Visit Time is required.');
        }

        Time parsedVisitTime;

        try {
            List<String> parts = visitTime.split(':');
            Integer hour = Integer.valueOf(parts[0]);
            Integer minute = Integer.valueOf(parts[1]);
            Integer second = 0;

            if (parts.size() > 2) {
                second = Integer.valueOf(parts[2].split('\\.')[0]);
            }

            parsedVisitTime = Time.newInstance(hour,minute,second, 0);

        } catch (Exception e) {
            throw new AuraHandledException('Invalid Visit Time: ' + visitTime);
        }

        Visit__c visit = new Visit__c();

        visit.Lead__c = leadId;
        visit.Opportunity__c = opportunityId;
        visit.Project__c = projectId;
        visit.Requirement_Type__c = requirementType;
        visit.Visit_Date__c = visitDate;
        visit.Visit_Time__c = parsedVisitTime;
        visit.Remarks__c = remarks;

        insert visit;

        Lead lead = [ SELECT Id, Status  FROM Lead WHERE Id = :leadId  LIMIT 1 ];
        Integer visitCount = [ SELECT COUNT()  FROM Visit__c WHERE Lead__c = :leadId ];
        if (visitCount == 1) {
            lead.Status = 'Site Visit Scheduled';
            update lead;
        }
        return visit.Id;
    }
    @AuraEnabled(cacheable=true)
    public static List<Visit__c> getVisits(Id recordId) {
        if (recordId == null) {
            return new List<Visit__c>();
        }
        String objectName = recordId.getSObjectType().getDescribe().getName();
        if (objectName == 'Lead') {
            return [SELECT Id,Name,Visit_Date__c, Visit_Time__c, Remarks__c,Requirement_Type__c,  Status__c,Project__c,Project__r.Name
                FROM Visit__c
                WHERE Lead__c = :recordId
                ORDER BY Visit_Date__c DESC, Visit_Time__c DESC
            ];
        } else if (objectName == 'Opportunity') {
            return [
                SELECT Id,Name, Visit_Date__c, Visit_Time__c,Remarks__c, Requirement_Type__c, Status__c, Project__c, Project__r.Name
                FROM Visit__c
                WHERE Opportunity__c = :recordId
                ORDER BY Visit_Date__c DESC, Visit_Time__c DESC
            ];
        }
        return new List<Visit__c>();
    }
    @AuraEnabled
    public static void updateVisitStatus( Id visitId,String status ) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (status != 'Completed' && status != 'Cancelled') {
            throw new AuraHandledException('Invalid Visit Status.');
        }
        Visit__c visit = [ SELECT Id,Status__c,Lead__c FROM Visit__c WHERE Id = :visitId  LIMIT 1  ];
        visit.Status__c = status;
        update visit;
        if (status == 'Completed' && visit.Lead__c != null) {
                List<Visit__c> visits = [ SELECT Id,Status__c,Lead__c, CreatedDate FROM Visit__c WHERE Lead__c = :visit.Lead__c ORDER BY CreatedDate ASC  ];
                if (!visits.isEmpty()) {
                    Visit__c firstVisit = visits[0];
                    if (firstVisit.Id == visit.Id) {
                        Lead lead = [ SELECT Id, Status FROM Lead WHERE Id = :visit.Lead__c  LIMIT 1   ];
                        lead.Status = 'Visited';
                        update lead;
                    }
                }
            }
        }
}