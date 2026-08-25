global class DailyVisitNotificationScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        try {
            List<Visit__c> visits = [ SELECT Id, Name, Status__c, Visit_Date__c, Visit_Time__c, Remarks__c, Project__r.Name,
                                            Lead__c, Lead__r.Name, Lead__r.OwnerId, Lead__r.Owner.Name, Lead__r.Owner.Email,
                                            Opportunity__c, Opportunity__r.Name, Opportunity__r.OwnerId, Opportunity__r.Owner.Name,
                                            Opportunity__r.Owner.Email
                                        FROM Visit__c
                                        WHERE Visit_Date__c = TODAY
                                        AND Status__c = 'Upcoming'
                                        ORDER BY Visit_Time__c
                                    ];
            if(visits.isEmpty()){
                return;
            }
            Map<String,List<Visit__c>> ownerVisitMap = new Map<String,List<Visit__c>>();
            for(Visit__c visit : visits){
                String ownerId;
                if(visit.Opportunity__r != null){
                    ownerId = visit.Opportunity__r.OwnerId;
                } else if (visit.Lead__c != null) {
                    ownerId = visit.Lead__r.OwnerId;
                }
                if (ownerId == null) {
                    continue;
                }
                if(!ownerVisitMap.containsKey(ownerId)){
                    ownerVisitMap.put(ownerId,new List<Visit__c>());
                }
                ownerVisitMap.get(ownerId).add(visit);
            }
            EmailTemplate template = [ SELECT Id, DeveloperName, Subject, HtmlValue
                                        FROM EmailTemplate
                                        WHERE DeveloperName='Daily_Visit_Reminder'
                                        LIMIT 1
                                    ];
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for(Id ownerId : ownerVisitMap.keySet()){
                List<Visit__c> ownerVisits = ownerVisitMap.get(ownerId);
                Visit__c firstVisit = ownerVisits[0];
                String ownerName;
                String ownerEmail;
                if (firstVisit.Opportunity__c != null) {
                    ownerName = firstVisit.Opportunity__r.Owner.Name;
                    ownerEmail = firstVisit.Opportunity__r.Owner.Email;
                } else {
                    ownerName = firstVisit.Lead__r.Owner.Name;
                    ownerEmail = firstVisit.Lead__r.Owner.Email;
                }
                String html = template.HtmlValue;
                html = html.replace('{!OwnerName}',ownerName);
                html = html.replace('{!VisitCount}',String.valueOf(ownerVisits.size()));
                html = html.replace('{!VisitTable}',generateVisitTable(ownerVisits));
                Messaging.SingleEmailMessage mail =new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ownerEmail});
                mail.setSubject(template.Subject);
                mail.setHtmlBody(html);
                mail.setSaveAsActivity(false);
                emails.add(mail);
            }
            if(!emails.isEmpty()){
                Messaging.sendEmail(emails);
            }
            CustomNotificationType notificationType = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName='Daily_Visit_Notification'
                LIMIT 1
            ];
            for(Id ownerId : ownerVisitMap.keySet()){
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(notificationType.Id);
                notification.setTitle('Today\'s Site Visits');
                notification.setBody(
                    'You have '
                    + ownerVisitMap.get(ownerId).size()
                    + ' visit(s) scheduled today.'
                );
                notification.setTargetPageRef(
                    JSON.serialize(new Map<String,Object>{
                        'type' => 'standard__objectPage',
                        'attributes' => new Map<String,Object>{
                            'objectApiName' => 'Visit__c',
                            'actionName' => 'list'
                        },
                        'state' => new Map<String,Object>{
                            'filterName' => 'Today_s_Visit'
                        }
                    })
                );
                notification.send(
                    new Set<String>{ ownerId }
                );
            }
        } catch(Exception e) {
            System.debug('Error while sending daily visit reminder ===> ' + e.getMessage() + 'at Line ===> ' + e.getLineNumber() + ' at Stack ===> ' + e.getStackTraceString());
        }
    }

    // method to generate visit table
    private static String generateVisitTable(List<Visit__c> visits){
        String html='';
        html+='<table style="border-collapse:collapse;width:100%;">';
        html+='<tr style="background:#0176d3;color:white;">';
        html+='<th style="padding:8px;text-align:left;">#</th>';
        html+='<th style="padding:8px;text-align:left;">Opportunity</th>';
        html+='<th style="padding:8px;text-align:left;">Time</th>';
        html+='<th style="padding:8px;text-align:left;">Project</th>';
        html+='<th style="padding:8px;text-align:left;">Remarks</th>';
        html+='</tr>';
        Integer i=1;
        for(Visit__c visit : visits){
            String customerName = '';
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            String visitUrl = baseUrl + '/' + visit.Id;
            if (visit.Opportunity__c != null) {
                customerName = visit.Opportunity__r.Name;
            } else if (visit.Lead__c != null) {
                customerName = visit.Lead__r.Name;
            }
            html+='<tr>';
            html+='<td style="padding:8px;border:1px solid #ddd;">'+i+'</td>';
            html+='<td style="padding:8px;border:1px solid #ddd;">'
                + '<a href="' + visitUrl + '">'
                + (String.isNotBlank(customerName) ? customerName : '-')
                + '</a>'
                + '</td>';
            html+='<td style="padding:8px;border:1px solid #ddd;">'
                +(visit.Visit_Time__c == null ? '-' : String.valueOf(visit.Visit_Time__c))
                +'</td>';
            html+='<td style="padding:8px;border:1px solid #ddd;">'
                + (visit.Project__r == null || visit.Project__r.Name == null ? '-' : visit.Project__r.Name)
                + '</td>';
            html+='<td style="padding:8px;border:1px solid #ddd;">'
                +(visit.Remarks__c == null ? '-' : visit.Remarks__c)
                +'</td>';
            html+='</tr>';
            i++;
        }
        html+='</table>';
        return html;
    }
}