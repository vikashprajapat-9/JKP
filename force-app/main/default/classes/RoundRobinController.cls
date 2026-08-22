public with sharing class RoundRobinController {

    @AuraEnabled
    public static Integer userFetchBreakTime() {
        try {
            String userId = UserInfo.getUserId();
            
            List<User_Tracking__c> userTrackingList = [SELECT Id FROM User_Tracking__c WHERE Member__c = :userId AND CreatedDate = TODAY LIMIT 1];
            System.debug('userTrackingList===>'+userTrackingList);
            if (userTrackingList.isEmpty()) {
                return 0;
            }
            User_Tracking__c userTracking = userTrackingList[0];
             System.debug('userTracking===>'+userTracking);
            List<User_Tracking_Audit__c> userAuditList = [
                SELECT Breakin_Datetime__c, BreakOut_Datetime__c
                FROM User_Tracking_Audit__c
                WHERE User_tracking__c = :userTracking.Id
                AND Breakin_Datetime__c != null
                AND BreakOut_Datetime__c != null
            ];
            System.debug('userAuditList===>'+userAuditList);
            Long totalElapsedSeconds = 0;
            for (User_Tracking_Audit__c audit : userAuditList) {
                if (audit.Breakin_Datetime__c != null && audit.BreakOut_Datetime__c != null) {
                    totalElapsedSeconds += (audit.BreakOut_Datetime__c.getTime() - audit.Breakin_Datetime__c.getTime()) / 1000;
                }
            }
    
            return totalElapsedSeconds.intValue();
        } catch (Exception e) {
            System.debug('Error fetching break time: ' + e.getMessage());
            return 0;
        }
    }
    
    
    
    @AuraEnabled
    public static String user_checkin(String userId) {
        try {
            List<User_Tracking__c> userTracking = [SELECT Id, Checkin_Datetime__c, Checkout_Datetime__c, Member__c FROM User_Tracking__c WHERE Member__c = :userId AND CreatedDate = TODAY LIMIT 1];
            if (!userTracking.isEmpty()) {
                User_Tracking__c trackingRecord = userTracking[0];
                if(trackingRecord.Checkout_Datetime__c != null){
                    System.debug('checkOut');
                    return 'checkOut';
             	}
                List<User_Tracking_Audit__c> userAudit = [SELECT Id, Name, Breakin_Datetime__c, BreakOut_Datetime__c FROM User_Tracking_Audit__c WHERE  User_tracking__c = :trackingRecord.Id AND Breakin_Datetime__c != null AND DAY_ONLY(CreatedDate) = TODAY ORDER BY CreatedDate DESC LIMIT 1];
                if (!userAudit.isEmpty()) {
                    if(userAudit[0].Breakin_Datetime__c != null && userAudit[0].BreakOut_Datetime__c == null){
                        System.debug('userAudit[0].Breakin_Datetime__c ===> ' + userAudit[0].Breakin_Datetime__c);
                        System.debug('userAudit[0].BreakOut_Datetime__c ===> ' + userAudit[0].BreakOut_Datetime__c);
                        System.debug('userTrackAuditBreakIn');
                        return 'userTrackAuditBreakIn';
                    }
                    System.debug('userTrackAudit');
                    return 'userTrackAudit'; 
                }else{
                    System.debug('nouserTrackAudit');
                    return 'nouserTrackAudit';  
                }
            }
            System.debug('NoUserTrack');
            return 'NoUserTrack';
        } catch (Exception e) {
            System.debug('stack trace ======> ' + e.getStackTraceString());
            return 'error';
        }
    }
    
    @AuraEnabled
    public static Boolean createUserTrackingRecord(String userId) {
        try {
            if (userId != null){
                list<User_Tracking__c> userTracking = new list<User_Tracking__c>();
                list<Assignment_Group_Member__c> agmList = new list<Assignment_Group_Member__c>();
                userTracking = [select id, Checkin_Datetime__c, Checkout_Datetime__c, Member__c from User_Tracking__c where Member__c = :userId and CreatedDate = TODAY limit 1];
                agmList = [select id, Group_Member__c, Assignment_Group__r.name from Assignment_Group_Member__c where Group_Member__c = :userId];
                if (userTracking.isEmpty()){
                    User_Tracking__c userTrackRec = new User_Tracking__c();
                    userTrackRec.Member__c = userId;
                    userTrackRec.Checkin_Datetime__c = DateTime.now();
                    insert userTrackRec;
                    if (!agmList.isEmpty()){
                        for (Assignment_Group_Member__c agm : agmList){
                            agm.Out_Of_Office__c = false;
                            
                        }
                        update agmList;
                        if(userTrackRec.Checkin_Datetime__c != null){
                           // SobjectLoadAssignment.ExecuteLoadAssignment(10);
                        }
                    }
                    
                } else{ 
                }  
            }
            //SobjectLoadAssignment.ExecuteLoadAssignment(5);
            return true;
        } catch (Exception e) {
            System.debug('Error creating user tracking record: ' + e.getMessage());
            return false;
        }
    }
    
    @AuraEnabled
    public static Boolean createUserAuditTrack(String userId, String action) {
        try {
            List<User_Tracking__c> userTrackingList = [SELECT Id FROM User_Tracking__c WHERE Member__c = :userId AND CreatedDate = TODAY LIMIT 1];
            if (userTrackingList.isEmpty()) {
                throw new AuraHandledException('No User_Tracking__c record found for today.');
            }
            User_Tracking__c userTracking = userTrackingList[0];
            userTracking.BreakTime_Started__c = true;
            update userTracking;
            User_Tracking_Audit__c newUserAuditTrack = new User_Tracking_Audit__c();
            newUserAuditTrack.User_tracking__c = userTracking.Id;
            newUserAuditTrack.Breakin_Datetime__c = System.now();
            insert newUserAuditTrack;
            list<Assignment_Group_Member__c> agmList = new list<Assignment_Group_Member__c>();
            agmList = [select id, Group_Member__c, Assignment_Group__r.name from Assignment_Group_Member__c where Group_Member__c = :userId];
            if(!agmList.isEmpty()){
                for (Assignment_Group_Member__c agm : agmList){
                    agm.BreakTime_Started__c = true; 
                }
                update agmList;
            }
            return true;
        } catch (Exception e) {
            System.debug('Error creating user audit track: ' + e.getMessage());
            return false;
        }
    }

    @AuraEnabled
    public static Boolean updateUserTrackingAudit(String userId, String action) {
        try {
            List<User_Tracking__c> userTrackingList = [SELECT Id FROM User_Tracking__c WHERE Member__c = :userId AND CreatedDate = TODAY LIMIT 1];
            if (userTrackingList.isEmpty()) {
                throw new AuraHandledException('No User_Tracking__c record found for today.');
            }
            User_Tracking__c userTracking = userTrackingList[0];
            userTracking.BreakTime_Started__c = false;
            update userTracking;
            
            User_Tracking_Audit__c userAudit = [Select Id,Name,Breakin_Datetime__c,BreakOut_Datetime__c From User_Tracking_Audit__c where User_tracking__c =:userTracking.ID And CreatedDate = TODAY AND Breakin_Datetime__c != null AND BreakOut_Datetime__c = null];
            userAudit.BreakOut_Datetime__c =  System.now();
            update userAudit;
            list<Assignment_Group_Member__c> agmList = new list<Assignment_Group_Member__c>();
            agmList = [select id, Group_Member__c, Assignment_Group__r.name from Assignment_Group_Member__c where Group_Member__c = :userId];
            if(!agmList.isEmpty()){
                for (Assignment_Group_Member__c agm : agmList){
                    agm.BreakTime_Started__c = false;
                }
                update agmList;
            }
            return true;
        } catch (Exception e) {
            System.debug('Error creating user audit track: ' + e.getMessage());
            return false;
        }
    }
    
    
    @AuraEnabled
    public static Boolean userCheckout(String userId) {
        try {
            list<Assignment_Group_Member__c> agmList = new list<Assignment_Group_Member__c>();
            User_Tracking__c userTracking = [SELECT Id, Checkout_Datetime__c FROM User_Tracking__c WHERE Member__c = :userId AND CreatedDate = TODAY LIMIT 1];
             agmList = [select id, Group_Member__c, Assignment_Group__r.name from Assignment_Group_Member__c where Group_Member__c = :userId];
             if (userTracking != null){
                    userTracking.Checkout_Datetime__c = DateTime.now();
                    update userTracking;
                    if (!agmList.isEmpty()){
                        for (Assignment_Group_Member__c agm : agmList){
                            agm.Out_Of_Office__c = true;
                        }
                        update agmList;
                    }
                    return true;
                }
                return false;
        } catch (Exception e) {
            throw new AuraHandledException('Error during user checkout: ' + e.getMessage());
        }
    }
}