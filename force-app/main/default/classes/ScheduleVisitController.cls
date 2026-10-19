public with sharing class ScheduleVisitController {

    @AuraEnabled
    public static Id createVisit(Id leadId,Id opportunityId,Id projectId,String requirementType,Date visitDate,String visitTime,String remarks, Id parentVisitId) {
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
            String timeValue = visitTime.trim().toUpperCase();
            Integer hour;
            Integer minute;
            Integer second = 0;
                Boolean isPM = timeValue.endsWith('PM');
                timeValue = timeValue.replace('AM', '').replace('PM', '').trim();
                List<String> parts = timeValue.split(':');
                hour = Integer.valueOf(parts[0]);
                minute = Integer.valueOf(parts[1]);
                if (parts.size() > 2) {
                    second = Integer.valueOf(parts[2].split('\\.')[0]);
                }
                if (isPM && hour != 12) {
                    hour += 12;
                } else if (!isPM && hour == 12) {
                    hour = 0;
                }
            parsedVisitTime = Time.newInstance(hour, minute, second, 0);

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
        if (parentVisitId != null) {
            visit.Visit__c = parentVisitId;
        }
        visit.Status__c = 'Upcoming';
        insert visit;
        if (parentVisitId != null) {
            Visit__c oldVisit = [SELECT Id, Status__c FROM Visit__c WHERE Id = :parentVisitId LIMIT 1];
            oldVisit.Status__c = 'Rescheduled';
            update oldVisit;
        }

        if (leadId != null) {
        Lead lead = [SELECT Id, Status FROM Lead WHERE Id = :leadId LIMIT 1 ];
        Integer visitCount = [SELECT COUNT()  FROM Visit__c WHERE Lead__c = :leadId ];

        if (visitCount == 1) {
            lead.Status = 'Site Visit Scheduled';
            update lead;
        }
    }
        return visit.Id;
    }
    @AuraEnabled(cacheable=true)
    public static Lead getLeadDetails(Id leadId) {
        if (leadId == null) {
            return null;
        }
        return [ SELECT Id,Unit_Type__c, Project__c FROM Lead WHERE Id = :leadId LIMIT 1];
    }
    @AuraEnabled(cacheable=true)
    public static Opportunity getOpportunityDetails(Id opportunityId) {

        if (opportunityId == null) {
            return null;
        }

        return [ SELECT Id,Project__c, Project__r.Name, Unit__c, Unit__r.Name,Unit__r.Unit_Type__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1 ];
    }
    @AuraEnabled
    public static List<Visit__c> getVisits(Id recordId) {
        List<Visit__c> result = new List<Visit__c>();

        if (recordId == null) {
            return result;
        }
        String objectName = recordId.getSObjectType().getDescribe().getName();
        List<Visit__c> visitRecords;
        if (objectName == 'Lead') {
            visitRecords = [SELECT Id,Name,Visit_Date__c, Visit_Time__c, Remarks__c,Requirement_Type__c,  Status__c,Project__c,Project__r.Name
                FROM Visit__c
                WHERE Lead__c = :recordId
                ORDER BY createdDate DESC
            ];
        } else if (objectName == 'Opportunity') {
            visitRecords = [
                SELECT Id,Name, Visit_Date__c, Visit_Time__c,Remarks__c, Requirement_Type__c, Status__c, Project__c, Project__r.Name
                FROM Visit__c
                WHERE Opportunity__c = :recordId
                ORDER BY createdDate DESC
            ];
        }
        for (Visit__c visit : visitRecords) {
            result.add(visit);
        }
        return result;
    }
    @AuraEnabled
    public static void updateVisitStatus(Id visitId, String status, String remarks) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (status != 'Completed' && status != 'Cancelled') {
            throw new AuraHandledException('Invalid Visit Status.');
        }
        if (status == 'Cancelled' && String.isBlank(remarks)) {
            throw new AuraHandledException('A cancellation reason is required.');
        }
        Visit__c visit = [ SELECT Id,Status__c,Lead__c FROM Visit__c WHERE Id = :visitId  LIMIT 1  ];
        visit.Status__c = status;
        if (status == 'Cancelled') {
            visit.Remarks__c = remarks.trim();
        }
        update visit;
        if (status == 'Completed' && visit.Lead__c != null) {
            Lead lead = [
                SELECT Id, Status
                FROM Lead
                WHERE Id = :visit.Lead__c
                LIMIT 1
            ];
            if (lead.Status == 'Site Visit Scheduled') {
                lead.Status = 'Visited';
                update lead;
            }
        }

    
}
}