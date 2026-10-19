public class SobjectLoadAssignmentHelper {
    Public Static Map<Id, Assignment_Group__c> rv_MapOfAGIdByAG = new Map<Id, Assignment_Group__c>();
    Public Static Map<Id, List<Assignment_Group_Member__c>> rv_MapOfAGIDByASMList = new Map<Id, List<Assignment_Group_Member__c>>();
      //MAIN ASSIGNMENT METHOD
    Public static void ExecuteSobjectOwnerAssignment( List<SObject> sObjectList,  String GroupId, Id queueId ) {
        System.debug('================ ASSIGNMENT START ================');
        System.debug('GroupId ==> ' + GroupId);
        System.debug('QueueId ==> ' + queueId);
        System.debug('sObjectList ==> ' + sObjectList);
        
         // CHECK BUSINESS HOURS
        BusinessHours defaultBH = [SELECT Id, TimeZoneSidKey FROM BusinessHours WHERE IsDefault = true LIMIT 1];
        Datetime currentTime = System.now();
        Boolean isWithinBusinessHours = BusinessHours.isWithin(defaultBH.Id, currentTime);
        System.debug('========== BUSINESS HOURS CHECK ==========');
        System.debug('Current GMT Time ==> ' + currentTime);
        System.debug('Business Hours Id ==> ' + defaultBH.Id);
        System.debug('Business Hours Time Zone ==> ' + defaultBH.TimeZoneSidKey);
        System.debug('Is Within Business Hours ==> ' + isWithinBusinessHours);
    
        if (!isWithinBusinessHours) {
            System.debug( 'OUTSIDE BUSINESS HOURS ==> LEAD ASSIGNMENT SKIPPED');
            return;
        }
        System.debug('INSIDE BUSINESS HOURS ==> LEAD ASSIGNMENT CONTINUES' );    
        System.debug('================ ASSIGNMENT START ================');

      //  Reassign_Lead__c reassignSetting =  Reassign_Lead__c.getInstance();
       // Boolean isRedistributionEnabled =   reassignSetting.Re_Distribute_Lead__c == true;
        Boolean isRedistributionEnabled = System.Label.Re_Distribute_Lead == 'true';
        System.debug( 'Re-distribution Enabled ==> ' +  isRedistributionEnabled  );
        //GET PREVIOUS OWNERS
        
        Map<Id, Set<Id>> previousOwnersByLead = new Map<Id, Set<Id>>();
        Set<Id> leadsRequiringManualRedistribution = new Set<Id>();
        if (isRedistributionEnabled) {
            Set<Id> leadIds =  new Set<Id>();
            for (SObject objectRec : sObjectList) {
                if (objectRec.get('Id') != null) {
                    leadIds.add(   (Id)objectRec.get('Id'));
                }
            }
            if (!leadIds.isEmpty()) {
                List<Lead_Assignment_History__c> historyList = [ SELECT Id,Lead__c,Lead_Assigned_To__c
                    FROM Lead_Assignment_History__c WHERE Lead__c IN :leadIds
                    AND Lead_Assigned_To__c != null
                ];
                for ( Lead_Assignment_History__c historyRec :historyList ) {
                    if ( !previousOwnersByLead.containsKey(historyRec.Lead__c)) {
                        previousOwnersByLead.put(historyRec.Lead__c,new Set<Id>() );
                    }
                    previousOwnersByLead .get(historyRec.Lead__c) .add(historyRec.Lead_Assigned_To__c);
                }
            }
            System.debug(  'Previous Owners By Lead ==> ' + previousOwnersByLead );
        }
        
        Integer lastAllocatedId = 0;

        rv_MapOfAGIdByAG = SobjectLoadAssignmentUtility.GetassigmentGroup();
        System.debug( 'rv_MapOfAGIdByAG ==> ' + rv_MapOfAGIdByAG );
       // SobjectLoadAssignment.GetAssignMentGroupMemberAndAssignmentGroup();
    
        Map<Id, List<Assignment_Group_Member__c>> assignmentGroupMembers =  SobjectLoadAssignmentUtility.assignmentGroupMembers();
        if (  assignmentGroupMembers.containsKey(GroupId) &&
            assignmentGroupMembers.get(GroupId) != null &&
            SobjectLoadAssignment.rv_MapOfAGIDByASMList.containsKey(GroupId) &&
            SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId) != null
        ) {
            if ( assignmentGroupMembers.get(GroupId).size() == SobjectLoadAssignment.rv_MapOfAGIDByASMList .get(GroupId)[0].Last_Allocated_RRID__c  ) {
                lastAllocatedId = 1;
            } else {
                if (rv_MapOfAGIdByAG.containsKey(GroupId) && rv_MapOfAGIdByAG.get(GroupId) != null ) {
                    Integer lastAllocatedRRId = rv_MapOfAGIdByAG.get(GroupId).Last_Allocated_RRid__c != null ?
                        ((Integer) rv_MapOfAGIdByAG.get(GroupId).Last_Allocated_RRid__c) + 1 : 1;

                    lastAllocatedId = lastAllocatedRRId;
                    System.debug( 'Initial lastAllocatedId ==> ' + lastAllocatedId );
                } else {
                    lastAllocatedId = 1;
                }
            }
        } else {
            lastAllocatedId = 1;
        }
    
        List<Assignment_Group_Member__c> groupMembers =  SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId);
        Integer totalMembers = 0;
        if (groupMembers != null) { 
            totalMembers = groupMembers.size();
        }
        System.debug(  'Total Members ==> ' +  totalMembers  );    
        Assignment_Group__c currentAssignmentGroup = rv_MapOfAGIdByAG.get(GroupId);
      
        Integer leadAssignmentTimeWindow = 30;
        Integer maxLeadAssignmentCount = 10;     
        if (currentAssignmentGroup != null) {
            if (currentAssignmentGroup.Lead_Assignment_Time_Window__c != null) {
                leadAssignmentTimeWindow =Integer.valueOf(String.valueOf( currentAssignmentGroup.Lead_Assignment_Time_Window__c));
            }      
            if (currentAssignmentGroup.Max_Lead_Assignment_Count__c != null) {
                maxLeadAssignmentCount =Integer.valueOf(String.valueOf(currentAssignmentGroup.Max_Lead_Assignment_Count__c));
            }
        }
        
        System.debug('Lead Assignment Time Window ==> ' +leadAssignmentTimeWindow +' minutes');      
        System.debug('Max Lead Assignment Count ==> ' + maxLeadAssignmentCount  );
        Set<Id> memberUserIds = new Set<Id>();
        if (groupMembers != null) {        
            for (Assignment_Group_Member__c agm : groupMembers) {        
                if (agm.Group_Member__c != null) {
                    memberUserIds.add(agm.Group_Member__c);
                }
            }
        }
        
        Map<Id, Integer> recentAssignmentCountByUser = getRecentLeadAssignmentCount(memberUserIds,leadAssignmentTimeWindow );
        System.debug( 'Recent Lead Assignment Count ==> ' + recentAssignmentCountByUser);

        Map<Id, Integer> caseCounts = SobjectLoadAssignmentUtility.getCaseCount(GroupId);
        Map<Id, Integer> inDisLeadCounts = SobjectLoadAssignmentUtility.getInDiscussionLeadsCount(GroupId);

        Map<Id, Boolean> agmSLA1BreachMap = getAGMSLA1BreachStatus(GroupId);
        Map<Id, Boolean> sla2BreachMap = getAGMSLA2BreachStatus(GroupId);

        Integer totalCaseCount = 0;
        for (Integer count : caseCounts.values()) {
            totalCaseCount += count;
        }
        System.debug( 'Initial Total Case Count ==> ' +     totalCaseCount );

        Set<Integer> numbers = new Set<Integer>();

        if (SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId) != null ) {
            for (Assignment_Group_Member__c agm :SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId)
            ) {
                if (agm.Assignment_Id__c != null) {
                    numbers.add( (Integer)agm.Assignment_Id__c );
                }
            }
        }
        Integer lastRId =  lastAllocatedId - 1;

        if ( rv_MapOfAGIdByAG.get(GroupId) != null &&
            ((Integer)rv_MapOfAGIdByAG.get(GroupId).Max_Sobject_Assignment_Count__c ) != null
        ) {
            Integer groupMaxAssignment =   ( (Integer) rv_MapOfAGIdByAG .get(GroupId).Max_Sobject_Assignment_Count__c  );
            if (groupMaxAssignment > totalCaseCount) {
                for (SObject objectRec : sObjectList) {
                    System.debug('------------------------------------------------' );
                    System.debug( 'Processing Lead ==> ' +objectRec.get('Id') );
                    String leadStatus = '';

                    if ( objectRec.get( 'Lead_Classification__c'  ) != null  ) {
                        leadStatus = String.valueOf(objectRec.get( 'Lead_Classification__c'));
                    }
                    Boolean isHot = leadStatus == 'Hot';

                    System.debug( 'Lead Classification ==> ' + leadStatus );
                    System.debug(  'Is Hot Lead ==> ' +  isHot);

                    List<Assignment_Group_Member__c> eligibleAGMs = new List<Assignment_Group_Member__c>();

                    for (  Assignment_Group_Member__c agm : SobjectLoadAssignment.rv_MapOfAGIDByASMList .get(GroupId) ) {
                        if (caseCounts.get(agm.Id) == null) {
                            caseCounts.put(  agm.Id,  0  );
                        }
                        Integer inDiscussionCount = 0;
                        if ( inDisLeadCounts.containsKey( agm.Id ) ) {
                            inDiscussionCount = inDisLeadCounts.get( agm.Id );
                        }
                       // Boolean hasHotLeadThres = (isHot &&  agm.In_Discussion_Lead_Threshold__c != null &&
                                //agm.In_Discussion_Lead_Threshold__c >inDiscussionCount  )  ||  !isHot;
                        Boolean hasHotLeadThres = !isHot || agm.In_Discussion_Lead_Threshold__c == null ||
                                agm.In_Discussion_Lead_Threshold__c > inDiscussionCount;
                        
                        // SLA1 STATUS                    
                        Boolean agmSLA1Breached = false;
                        if ( agmSLA1BreachMap.containsKey( agm.Id ) ) {
                            agmSLA1Breached =  agmSLA1BreachMap.get(agm.Id);
                        }
                          //SLA2 STATUS
                
                        Boolean sla2Breached = false;
                        if (sla2BreachMap.containsKey(agm.Id)) {
                            sla2Breached = sla2BreachMap.get(agm.Id );
                        }
                
                        Boolean slaEligible = true;
                        if (isHot && (agmSLA1Breached ||sla2Breached)) {
                            slaEligible = false;
                        }
                        //
                        Integer recentAssignmentCount = 0;                        
                        if (agm.Group_Member__c != null &&
                            recentAssignmentCountByUser.containsKey(agm.Group_Member__c)) {                     
                            recentAssignmentCount =recentAssignmentCountByUser.get(agm.Group_Member__c);
                        }                        
                        Boolean leadAssignmentLimitAvailable = recentAssignmentCount < maxLeadAssignmentCount;                       
                        System.debug( '30 MIN LEAD LIMIT ==> ' +'AGM=' + agm.Id +', User=' + agm.Group_Member__c + ', Assigned In Window=' + recentAssignmentCount + ', Max Allowed=' + maxLeadAssignmentCount +', Eligible=' + leadAssignmentLimitAvailable);
                       
                        //STATUS CHECK
                        Boolean basicEligible =  agm.Max_Sobject_Assignment_Count__c != null &&
                            agm.Max_Sobject_Assignment_Count__c > caseCounts.get(agm.Id)  &&
                            agm.BreakTime_Started__c == false  &&
                            !agm.Out_Of_Office__c  && agm.Active__c == true  &&  hasHotLeadThres && leadAssignmentLimitAvailable;
                            
                            //REDISTRIBUTION CHECK
                        Boolean alreadyAssignedToThisUser =false;
                        if (isRedistributionEnabled) {
                            Id currentLeadId =   (Id)objectRec.get('Id');
                            if ( previousOwnersByLead.containsKey(  currentLeadId )
                            ) {
                                Set<Id> previousOwners =  previousOwnersByLead.get(currentLeadId);
                                if (  previousOwners != null &&  previousOwners.contains( agm.Group_Member__c ) ) {
                                    alreadyAssignedToThisUser =  true;
                                }
                            }
                            System.debug( 'REDISTRIBUTION CHECK ==> ' +  'Lead=' + currentLeadId + ', AGM=' + agm.Id + ', User=' + agm.Group_Member__c +   ', Already Assigned=' + alreadyAssignedToThisUser );
                        }

                        Boolean redistributionEligible = !isRedistributionEnabled || !alreadyAssignedToThisUser;
                        Boolean finalEligible = basicEligible &&  slaEligible && redistributionEligible;

                        System.debug('AGM ELIGIBILITY ==> ' +'AGM=' + agm.Id + ', User=' + agm.Group_Member__c +
                            ', AssignmentId=' +agm.Assignment_Id__c +', Hot=' + isHot +
                            ', SLA1Breached=' +agmSLA1Breached +', SLA2Breached=' +sla2Breached +
                            ', SLAEligible=' + slaEligible +', BasicEligible=' + basicEligible +
                            ', RedistributionEligible=' +  redistributionEligible +', FINAL=' + finalEligible  );
                        if (finalEligible) {
                            eligibleAGMs.add( agm );
                        }
                    }
                    if (eligibleAGMs.isEmpty()) {
                        System.debug( 'NO ELIGIBLE AGM ==> Lead remains in Queue. ' +  'Lead=' + objectRec.get('Id') +  ', Classification=' + leadStatus );
                        leadsRequiringManualRedistribution.add((Id)objectRec.get('Id'));
                        continue;
                    }
                    System.debug( 'Eligible AGM Count ==> ' + eligibleAGMs.size() );
                    
                    Assignment_Group_Member__c selectedAGM = findNextEligibleAGM( eligibleAGMs,lastAllocatedId, numbers );
                    if (selectedAGM == null) {
                        System.debug('NO ROUND ROBIN AGM FOUND ==> ' +  'Lead remains in Queue. Lead=' + objectRec.get('Id'));
                        continue;
                    }

                     //ASSIGN LEAD
            
                    System.debug(  'SELECTED AGM ==> ' + selectedAGM.Id );
                    System.debug( 'SELECTED USER ==> ' + selectedAGM.Group_Member__c );
                    System.debug('SELECTED ASSIGNMENT ID ==> ' + selectedAGM.Assignment_Id__c   );
                    
                    if ( objectRec.get('OwnerId') != selectedAGM.Group_Member__c  ) {
                        objectRec.put( 'OwnerId',selectedAGM.Group_Member__c );
                        objectRec.put( 'Pre_Sales_Team_Member__c', selectedAGM.Group_Member__c  );
                        objectRec.put('AGM_Related_to__c', selectedAGM.Id );
                        objectRec.put( 'AG_Related_to__c', selectedAGM.Assignment_Group__c );
                        objectRec.put(  'Is_User_Assigned__c', true );
                
                        if (  objectRec.get('Status') == 'New' ||objectRec.get('Status') == null ) {
                            objectRec.put('Status','Assigned' );
                        }
                        objectRec.put( 'Lead_Assigned_Date_Time__c',  Datetime.now());
                        Id selectedUserId = selectedAGM.Group_Member__c;                    
                        if (selectedUserId != null) {                   
                            if (!recentAssignmentCountByUser.containsKey(selectedUserId)) {                    
                                recentAssignmentCountByUser.put(selectedUserId, 0);
                            }                    
                            recentAssignmentCountByUser.put(selectedUserId, recentAssignmentCountByUser.get(selectedUserId) + 1);                    
                            System.debug( 'UPDATED RECENT COUNT ==> ' + 'User=' + selectedUserId +', Count=' + recentAssignmentCountByUser.get(selectedUserId ));
                        }

                        totalCaseCount++;
                        caseCounts.put(  selectedAGM.Id, caseCounts.get( selectedAGM.Id ) + 1  );
                        lastRId =(Integer)selectedAGM.Assignment_Id__c;
                        lastAllocatedId = getNextAssignmentId(  Integer.valueOf(String.valueOf(selectedAGM.Assignment_Id__c)), numbers );

                        System.debug( 'LEAD ASSIGNED SUCCESSFULLY ==> ' + 'Lead=' + objectRec.get('Id') +
                            ', User=' + selectedAGM.Group_Member__c +', AGM=' +selectedAGM.Id + ', Next RR=' +  lastAllocatedId);
                    }
                }
                //UPDATE ASSIGNMENT GROUP
                
                if (!sObjectList.isEmpty()) {
                    Assignment_Group__c ov_AGTobeUpdated = new Assignment_Group__c();
                    ov_AGTobeUpdated.Id = rv_MapOfAGIdByAG .get(GroupId) .Id;

                    if (lastRId > 0) {
                        ov_AGTobeUpdated.Last_Allocated_RRid__c = lastRId;
                        Database.SaveResult agUpdateResult =  Database.update(  ov_AGTobeUpdated, false  );
                        if (!agUpdateResult.isSuccess()) {
                            for (Database.Error err :  agUpdateResult.getErrors() ) {
                                System.debug( 'Assignment Group update failed: ' + err.getMessage() );
                            }
                        }

                    }
                      //UPDATE LEADS
                    Database.SaveResult[] sObjectUpdateResults = Database.update( sObjectList,  false  );
                    for (  Database.SaveResult result :  sObjectUpdateResults ) {
                        if (!result.isSuccess()) {
                            for ( Database.Error err : result.getErrors() ) {
                                System.debug( 'SObject update failed: ' +  err.getMessage() );
                            }
                        }
                    }
                }
                if (!leadsRequiringManualRedistribution.isEmpty()) {
                      System.debug('Leads requiring manual redistribution ==> ' +  leadsRequiringManualRedistribution );
                    notifySSMForUnassignedLeads( leadsRequiringManualRedistribution);
                }

            } else {
                System.debug( 'ASSIGNMENT GROUP MAX CAPACITY REACHED ==> ' + 'Max=' + groupMaxAssignment +', Current=' + totalCaseCount  );
            }
        }
        System.debug(  '================ ASSIGNMENT END ================'  );
    }
    
     //FIND NEXT ELIGIBLE AGM
    private static Assignment_Group_Member__c findNextEligibleAGM( List<Assignment_Group_Member__c> eligibleAGMs, Integer startingRRId,  Set<Integer> allAssignmentIds   ) {

        if ( eligibleAGMs == null || eligibleAGMs.isEmpty()  ) {
            return null;
        }
        for (  Assignment_Group_Member__c agm : eligibleAGMs  ) {

            if ( agm.Assignment_Id__c != null && agm.Assignment_Id__c == startingRRId ) {
                return agm;
            }
        }
    
        List<Integer> sortedEligibleIds = new List<Integer>();
        for ( Assignment_Group_Member__c agm :  eligibleAGMs  ) {
            if (agm.Assignment_Id__c != null) {
                sortedEligibleIds.add( (Integer)agm.Assignment_Id__c   );
            }
        }
        sortedEligibleIds.sort();
    
        for (Integer eligibleId : sortedEligibleIds  ) {
            if (eligibleId > startingRRId) {
                for ( Assignment_Group_Member__c agm :  eligibleAGMs ) {
                    if (agm.Assignment_Id__c ==  eligibleId) {
                        return agm;
                    }
                }
            }
        }
        for ( Integer eligibleId : sortedEligibleIds ) {
            for (Assignment_Group_Member__c agm : eligibleAGMs  ) {
                if (agm.Assignment_Id__c == eligibleId   ) {
                    return agm;
                }
            }
        }
        return null;
    }
     //GET NEXT ROUND ROBIN ID
    private static Integer getNextAssignmentId(Integer currentAssignmentId,Set<Integer> assignmentIds ) {
        if (assignmentIds == null ||  assignmentIds.isEmpty()   ) {

            return 1;
        }
        List<Integer> sortedIds =new List<Integer>(  assignmentIds  );
        sortedIds.sort();
        for ( Integer assignmentId : sortedIds ) {
            if ( assignmentId > currentAssignmentId  ) {
                return assignmentId;
            }
        }
        return sortedIds[0];
    }
    
   /* private static Map<Id, Integer> getRecentLeadAssignmentCount(Set<Id> userIds,Integer timeWindowMinutes) {  
        Map<Id, Integer> recentCountByUser = new Map<Id, Integer>();
        if (userIds == null || userIds.isEmpty() || timeWindowMinutes == null || timeWindowMinutes <= 0) {
            return recentCountByUser;
        }
        //Datetime windowStart = Datetime.now().addMinutes(-timeWindowMinutes);
        BusinessHours defaultBH = [ SELECT Id, TimeZoneSidKey FROM BusinessHours WHERE IsDefault = true LIMIT 1 ];
        Datetime nowTime = System.now();
        // Convert current time to Business Hours timezone
        String localDateTimeString =nowTime.format('yyyy-MM-dd HH:mm:ss',defaultBH.TimeZoneSidKey  );
        Datetime localNow = Datetime.valueOf(localDateTimeString);
        Integer currentMinute = localNow.minute();
    
        Integer slotMinute;
    
        if (currentMinute < 30) {
            slotMinute = 0;
        } else {
            slotMinute = 30;
        }
    
        Datetime localSlotStart = Datetime.newInstance( localNow.date(),Time.newInstance( localNow.hour(),slotMinute, 0,0) );
        Datetime localSlotEnd = localSlotStart.addMinutes(timeWindowMinutes);
        // Convert local slot times back to GMT
        Long startOffset = TimeZone.getTimeZone(defaultBH.TimeZoneSidKey) .getOffset(nowTime);
        Datetime slotStart = localSlotStart.addMilliseconds(-startOffset);
        Datetime slotEnd =localSlotEnd.addMilliseconds(-startOffset);
            
        System.debug('========== 30 MIN LEAD ASSIGNMENT CHECK ==========');
        System.debug('Current GMT Time ==> ' + nowTime);
        System.debug('Business Hours Time Zone ==> ' + defaultBH.TimeZoneSidKey);
        System.debug('Local Business Time ==> ' + localNow);
        System.debug( 'Current Minute ==> ' + currentMinute);
        System.debug( 'Slot Start Local ==> ' + localSlotStart );
        System.debug( 'Slot End Local ==> ' + localSlotEnd );    
        System.debug('Slot Start GMT ==> ' + slotStart  );
        System.debug( 'Slot End GMT ==> ' +slotEnd );    
        System.debug( 'Users Being Checked ==> ' + userIds );
        for (Lead_Assignment_History__c historyRec : [
            SELECT Id,Lead_Assigned_To__c,CreatedDate
            FROM Lead_Assignment_History__c
            WHERE Lead_Assigned_To__c IN :userIds
            AND CreatedDate >= :slotStart
            AND CreatedDate < :slotEnd
        ]) {
            Id userId = historyRec.Lead_Assigned_To__c;
            if (!recentCountByUser.containsKey(userId)) {
                recentCountByUser.put(userId, 0);
            }
            recentCountByUser.put(userId,recentCountByUser.get(userId) + 1);
            System.debug('HISTORY FOUND ==> User=' + userId +', HistoryId=' + historyRec.Id +', CreatedDate=' + historyRec.CreatedDate);
        }
        System.debug('FINAL 30 MIN ASSIGNMENT COUNTS ==> ' +  recentCountByUser);
        return recentCountByUser;
    }*/
    private static Map<Id, Integer> getRecentLeadAssignmentCount( Set<Id> userIds, Integer timeWindowMinutes) {
        Map<Id, Integer> assignmentCountByUser = new Map<Id, Integer>();
        if ( userIds == null || userIds.isEmpty() ||timeWindowMinutes == null || timeWindowMinutes <= 0) {
            return assignmentCountByUser;
        }
        BusinessHours defaultBH = [  SELECT Id, TimeZoneSidKey FROM BusinessHours  WHERE IsDefault = true LIMIT 1 ];
        Datetime nowTime = System.now();
        String localDateTimeString = nowTime.format(  'yyyy-MM-dd HH:mm:ss', defaultBH.TimeZoneSidKey );
        Datetime localNow = Datetime.valueOfGmt(localDateTimeString);
        Integer currentMinute = localNow.minute();
        Integer slotMinute = currentMinute < 30 ? 0 : 30;
        Datetime localSlotStart = Datetime.newInstance(localNow.date(),  Time.newInstance(localNow.hour(),  slotMinute,0, 0 ));
        Datetime localSlotEnd =localSlotStart.addMinutes(timeWindowMinutes);
        TimeZone businessTimeZone = TimeZone.getTimeZone(defaultBH.TimeZoneSidKey);
        Long offsetMillis = businessTimeZone.getOffset(nowTime);
        Integer offsetSeconds = Integer.valueOf(offsetMillis / 1000);
        Datetime slotStart = localSlotStart.addSeconds(-offsetSeconds);
        Datetime slotEnd = localSlotEnd.addSeconds(-offsetSeconds);
    
        System.debug( '========== 30 MIN LEAD ASSIGNMENT CHECK =========='  );
        System.debug( 'Current UTC Time ==> ' + nowTime );
        System.debug( 'Business Hours Time Zone ==> ' +  defaultBH.TimeZoneSidKey );
        System.debug( 'Business Hours Offset Seconds ==> ' +  offsetSeconds  );
        System.debug( 'Local Business Time ==> ' +  localDateTimeString );
        System.debug(  'Current Minute ==> ' +currentMinute);
        System.debug( 'Slot Start Local ==> ' + localSlotStart  );
        System.debug(  'Slot End Local ==> ' +localSlotEnd );
        System.debug( 'Slot Start UTC ==> ' +slotStart  );
        System.debug( 'Slot End UTC ==> ' +  slotEnd  );
        System.debug( 'Users Being Checked ==> ' +  userIds);
    
        for (Lead leadRec : [ SELECT Id, AGM_Related_to__c,Lead_Assigned_Date_Time__c,Pre_Sales_Team_Member__c FROM Lead
            WHERE Pre_Sales_Team_Member__c IN :userIds
            AND Lead_Assigned_Date_Time__c >= :slotStart
            AND Lead_Assigned_Date_Time__c < :slotEnd
        ]) {
             System.debug(leadRec.Id + ' | ' + leadRec.Lead_Assigned_Date_Time__c);
            Id userId = leadRec.Pre_Sales_Team_Member__c;
            if (userId == null) {
                continue;
            }
            Integer currentCount =assignmentCountByUser.containsKey(userId)? assignmentCountByUser.get(userId)  : 0;
            currentCount++;
            assignmentCountByUser.put( userId, currentCount );
            System.debug('LEAD FOUND IN CURRENT SLOT ==> ' + 'Lead=' + leadRec.Id + ', User=' + userId +  ', AssignedTime=' + leadRec.Lead_Assigned_Date_Time__c );
        }
        for (Id userId : userIds) {
            if (!assignmentCountByUser.containsKey(userId)) {
                assignmentCountByUser.put(userId, 0);
            }
        }
        System.debug( 'FINAL 30 MIN ASSIGNMENT COUNTS ==> ' + assignmentCountByUser );
        return assignmentCountByUser;
    }
    private static Map<Id, Boolean> getAGMSLA1BreachStatus(String GroupId ) {
        Map<Id, Boolean> agmSLA1BreachMap = new Map<Id, Boolean>();
        List<Assignment_Group_Member__c> agmList = SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId);
        if (  agmList == null || agmList.isEmpty() ) {
            return agmSLA1BreachMap;
        }
        /*
         * Map User ID -> AGM
         */
        Map<Id, Assignment_Group_Member__c> agmByUserId = new Map<Id, Assignment_Group_Member__c>();
        Set<Id> userIds =  new Set<Id>();

        for ( Assignment_Group_Member__c agm :agmList ) {
            if (agm.Group_Member__c != null ) {
                userIds.add(agm.Group_Member__c );
                agmByUserId.put(agm.Group_Member__c,  agm );
            }
        }
       //Default SLA1 period = 1 month
        Integer periodMonths = 1;       
        Assignment_Group__c assignmentGroup =rv_MapOfAGIdByAG.get(GroupId);        
        if (assignmentGroup != null &&
            assignmentGroup.SLA1_Period__c != null) {        
            periodMonths = Integer.valueOf(String.valueOf(assignmentGroup.SLA1_Period__c));
        }
        Date periodStartDate =  Date.today().addMonths(-periodMonths);
        Datetime periodStartDateTime = Datetime.newInstance(periodStartDate,Time.newInstance(0,0,0, 0) );
        
        List<Lead_Assignment_History__c> historyList = [ SELECT Id,Lead__c, Lead_Assigned_To__c,
                SLA1__c, CreatedDate FROM Lead_Assignment_History__c
            WHERE Lead_Assigned_To__c IN :userIds AND CreatedDate >= :periodStartDateTime   ];

        Map<Id, Integer> totalAssignedByAGM = new Map<Id, Integer>();
        Map<Id, Integer> sla1BreachedByAGM =new Map<Id, Integer>();

        for ( Lead_Assignment_History__c historyRec : historyList ) {
            if ( historyRec.Lead_Assigned_To__c == null ||!agmByUserId.containsKey( historyRec.Lead_Assigned_To__c  )) {
                continue;
            }
            Id agmId = agmByUserId.get(historyRec.Lead_Assigned_To__c).Id;
            Integer totalCount =totalAssignedByAGM.containsKey(agmId) ? totalAssignedByAGM.get( agmId): 0;
            totalAssignedByAGM.put( agmId, totalCount + 1 );
            if ( historyRec.SLA1__c == true ) {
                Integer breachCount = sla1BreachedByAGM.containsKey( agmId )  ? sla1BreachedByAGM.get(agmId) : 0;
                sla1BreachedByAGM.put( agmId,breachCount + 1 );
            }
        }

        for ( Assignment_Group_Member__c agm : agmList ) {
            Integer totalAssigned = totalAssignedByAGM.containsKey(agm.Id ) ? totalAssignedByAGM.get(agm.Id)  :  0;
            Integer breached = sla1BreachedByAGM.containsKey( agm.Id  )? sla1BreachedByAGM.get(agm.Id)  : 0;
            Boolean sla1Breached = false;
            if (totalAssigned > 0) {
               Decimal thresholdPercentage = 10;
                if (assignmentGroup != null && assignmentGroup.SLA1_Threshold_Percentage__c != null) {                
                    thresholdPercentage = assignmentGroup.SLA1_Threshold_Percentage__c;
                }
                Decimal breachPercentage = (Decimal.valueOf(breached) / Decimal.valueOf(totalAssigned))* 100;
                sla1Breached =  breachPercentage >= thresholdPercentage;

                System.debug( '========== SLA1 DETAILS ==========' );
                System.debug( 'AGM = ' +agm.Id);
                System.debug( 'Total Assigned = ' +  totalAssigned);
                System.debug( 'SLA1 Breached Leads = ' +  breached );
                System.debug(  'SLA1 Breach % = ' + breachPercentage  );
                System.debug( 'SLA1 Threshold % = ' + thresholdPercentage  );
                System.debug('SLA1 AGM Breached = ' + sla1Breached  );
                System.debug(  '===================================' );
            }
            agmSLA1BreachMap.put(  agm.Id, sla1Breached);
        }
        return agmSLA1BreachMap;
    }

    private static Map<Id, Boolean> getAGMSLA2BreachStatus( String GroupId) {
        Map<Id, Boolean> sla2BreachMap = new Map<Id, Boolean>();
        List<Assignment_Group_Member__c> agmList = SobjectLoadAssignment.rv_MapOfAGIDByASMList.get(GroupId);

        if ( agmList == null || agmList.isEmpty()  ) {
            return sla2BreachMap;
        }

         //Map User ID -> AGM
    
        Map<Id, Assignment_Group_Member__c> agmByUserId = new Map<Id, Assignment_Group_Member__c>();

        Set<Id> userIds = new Set<Id>();
        for (Assignment_Group_Member__c agm :agmList  ) {
            if ( agm.Group_Member__c != null  ) {
                userIds.add( agm.Group_Member__c );
                agmByUserId.put(agm.Group_Member__c, agm  );
            }
        }
       //SLA2 period = 2 months
    
        Integer sla2PeriodMonths = 2;            
        Assignment_Group__c assignmentGroup = rv_MapOfAGIdByAG.get(GroupId);            
        if (assignmentGroup != null & assignmentGroup.SLA2_Period__c != null) {           
            sla2PeriodMonths =Integer.valueOf(String.valueOf( assignmentGroup.SLA2_Period__c));
        }
        Date periodStartDate = Date.today().addMonths(-sla2PeriodMonths  );
        Datetime periodStartDateTime = Datetime.newInstance( periodStartDate,Time.newInstance( 0,  0, 0,0  ) );
    
        List<Lead_Assignment_History__c> historyList = [ SELECT Id,  Lead__c,
                Lead_Assigned_To__c,SLA2__c,  CreatedDate
            FROM Lead_Assignment_History__c
            WHERE Lead_Assigned_To__c IN :userIds
            AND CreatedDate >= :periodStartDateTime
        ];

        Map<Id, Integer> totalAssignedByAGM = new Map<Id, Integer>();
        Map<Id, Integer> sla2BreachedByAGM = new Map<Id, Integer>();

        for ( Lead_Assignment_History__c historyRec : historyList   ) {
            if ( historyRec.Lead_Assigned_To__c == null  ) {
                continue;
            }
            if ( !agmByUserId.containsKey( historyRec.Lead_Assigned_To__c)  ) {
                continue;
            }
            Id agmId = agmByUserId.get(  historyRec.Lead_Assigned_To__c   )  .Id;
            Integer totalCount = totalAssignedByAGM.containsKey( agmId) ? totalAssignedByAGM.get( agmId   )  :  0;
            totalAssignedByAGM.put(  agmId, totalCount + 1  );
            if ( historyRec.SLA2__c == true  ) {
                Integer breachCount = sla2BreachedByAGM.containsKey(  agmId ) ? sla2BreachedByAGM.get( agmId) :  0;
                sla2BreachedByAGM.put( agmId, breachCount + 1 );
            }
        }
        //Calculate breach percentage
        
        for ( Assignment_Group_Member__c agm : agmList   ) {
            Integer totalAssigned = totalAssignedByAGM.containsKey(  agm.Id  ) ? totalAssignedByAGM.get( agm.Id  )  :  0;
            Integer breached = sla2BreachedByAGM.containsKey( agm.Id   )  ? sla2BreachedByAGM.get( agm.Id ) : 0;
            Boolean sla2Breached = false;

            if (totalAssigned > 0) {
                Decimal thresholdPercentage = 10;                
                if (assignmentGroup != null && assignmentGroup.SLA2_Threshold_Percentage__c != null) {                
                    thresholdPercentage = assignmentGroup.SLA2_Threshold_Percentage__c;
                }
                Decimal breachPercentage = (Decimal.valueOf( breached ) / Decimal.valueOf(totalAssigned) ) * 100;

                sla2Breached = breachPercentage >= thresholdPercentage;

                System.debug('========== SLA2 DETAILS =========='  );
                System.debug(  'AGM = ' +  agm.Id  );
                System.debug( 'SLA2 Period Months = ' + sla2PeriodMonths );
                System.debug( 'Period Start = ' + periodStartDateTime  );
                System.debug( 'Total Assigned = ' +  totalAssigned  );
                System.debug( 'SLA2 Breached Leads = ' + breached );
                System.debug( 'SLA2 Breach % = ' + breachPercentage);
                System.debug( 'SLA2 Threshold % = ' + thresholdPercentage );
                System.debug('SLA2 AGM Breached = ' + sla2Breached );
                System.debug( '===================================' );
            }

            sla2BreachMap.put(agm.Id,sla2Breached);
        }
        return sla2BreachMap;
    }

    // private static void notifySSMForUnassignedLeads(Set<Id> leadIds) {
    //     if (leadIds == null || leadIds.isEmpty()) {
    //         return;
    //     }
    //     List<Lead> leads = [SELECT Id, Name, Lead_Classification__c, Status, AG_Related_to__c FROM Lead WHERE Id IN :leadIds];
    //     if (leads.isEmpty()) {
    //         return;
    //     }
    //     EmailTemplate emailTemplate = [ SELECT Id, Subject, HtmlValue, Body FROM EmailTemplate WHERE DeveloperName = 'Lead_Assignment_No_Eligible_Advisor' LIMIT 1 ];
    //     List<User> ssmUsers = [SELECT Id, FirstName, LastName, Email FROM User  WHERE IsActive = true AND UserRole.Name = 'SSM' ];
    //     if (ssmUsers.isEmpty()) {
    //         System.debug('No active SSM users found.');
    //         return;
    //     }
    //     List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    //     List<Messaging.CustomNotification> notifications =new List<Messaging.CustomNotification>();
    //     String baseUrl = URL.getSalesforceBaseUrl().toExternalForm();
    //     for (Lead leadRec : leads) {
    //         String leadUrl = baseUrl + '/' + leadRec.Id;
    //         for (User ssm : ssmUsers) {
    //             if (String.isBlank(ssm.Email)) {
    //                 continue;
    //             }
    //             String subject = emailTemplate.Subject;
    //             subject = subject.replace('{!Lead.Name}',leadRec.Name != null ? leadRec.Name : '' );
    //             String body = emailTemplate.HtmlValue;
    //             if (String.isBlank(body)) {
    //                 body = emailTemplate.Body;
    //             }

    //             body = body.replace('{!User.FirstName}', ssm.FirstName != null ? ssm.FirstName : '' );
    //             body = body.replace('{!Lead.Name}',leadRec.Name != null ? leadRec.Name : '');
    //             body = body.replace('{!Lead.Id}', String.valueOf(leadRec.Id));
    //             body = body.replace('{!Lead.Lead_Classification__c}', leadRec.Lead_Classification__c != null ? leadRec.Lead_Classification__c : '' );
    //             body = body.replace('{!Lead.Status}', leadRec.Status != null? leadRec.Status : '' );
    //             body = body.replace('{!Lead.AG_Related_to__c}',leadRec.AG_Related_to__c != null ? String.valueOf(leadRec.AG_Related_to__c)  : '' );
    //             body = body.replace( '{!Lead.Link}', '<a href="' + leadUrl + '">View Lead</a>'  );

    //             Messaging.SingleEmailMessage email =  new Messaging.SingleEmailMessage();
    //             email.setToAddresses(  new List<String>{ ssm.Email });
    //             email.setSubject(subject);
    //             email.setHtmlBody(body);
    //             emails.add(email);
    //         }
    //     }
    //     if (!emails.isEmpty()) {
    //         Messaging.sendEmail(emails);
    //     }
    // }

    private static void notifySSMForUnassignedLeads(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }
        Id ssmUserId = '005f6000004dGI1AAM';
        User ssmUser = [ SELECT Id, FirstName, LastName, Email, IsActive FROM User WHERE Id = :ssmUserId  AND IsActive = true  LIMIT 1 ];
        if (String.isBlank(ssmUser.Email)) {
            System.debug( 'SSM does not have an email address. UserId=' + ssmUserId );
            return;
        }
        EmailTemplate template = [ SELECT Id, DeveloperName, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Lead_Assignment_No_Eligible_Advisor'
            LIMIT 1 ];

        List<Lead> leads = [ SELECT Id, Name, Lead_Classification__c, Status, AG_Related_to__c FROM Lead WHERE Id IN :leadIds ];
        Id notificationTypeId;
        try {
            notificationTypeId = [ SELECT Id FROM CustomNotificationType  WHERE DeveloperName = 'Lead_Assignment_Alert' LIMIT 1  ].Id;
        } catch (Exception e) {
            System.debug( 'Custom Notification is not available. ' + 'Email notification will still be sent. Error=' + e.getMessage());
        }
        List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();
        for (Lead leadRec : leads) {
            String leadUrl = URL.getOrgDomainUrl().toExternalForm() +  '/' + leadRec.Id;
            String body;
            if (!String.isBlank(template.HtmlValue)) {
                body = template.HtmlValue;
            } else {
                body = template.Body;
            }
            body = body.replace('{!User.FirstName}', ssmUser.FirstName == null ? '' : ssmUser.FirstName);
            body = body.replace('{!Lead.Name}', leadRec.Name == null ? '' : leadRec.Name);
            body = body.replace('{!Lead.Id}',String.valueOf(leadRec.Id));
            body = body.replace( '{!Lead.Lead_Classification__c}', leadRec.Lead_Classification__c == null ? ''
                    : leadRec.Lead_Classification__c);
            body = body.replace('{!Lead.Status}', leadRec.Status == null ? '' : leadRec.Status);
            body = body.replace('{!Lead.AG_Related_to__c}',leadRec.AG_Related_to__c == null ? '': leadRec.AG_Related_to__c );
            body = body.replace('{!Lead.Link}','<a href="' + leadUrl + '">View Lead</a>');

            String subject = template.Subject;
            if (String.isBlank(subject)) {
                subject = 'Lead Assignment Requires Manual Action';
            }
            subject = subject.replace( '{!User.FirstName}',ssmUser.FirstName == null ? '' : ssmUser.FirstName );
            subject = subject.replace( '{!Lead.Name}', leadRec.Name == null ? '' : leadRec.Name  );
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses( new List<String>{ ssmUser.Email});
            email.setSubject(subject);
            email.setHtmlBody(body);
            emailMessages.add(email);

            if (notificationTypeId != null) {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypeId );
                    notification.setTitle( 'Lead Assignment Requires Manual Action' );
                    notification.setBody('No eligible advisor was found for Lead ' + leadRec.Name +
                        '. Please manually redistribute this lead.' );
                    notification.setTargetId(leadRec.Id);
                    //notification.setRecipientIds( new Set<String>{String.valueOf(ssmUserId)});
                    notification.send(new Set<String>{ssmUserId});
                    System.debug('Custom notification sent for Lead=' + leadRec.Id);

                } catch (Exception e) {
                    System.debug('Custom notification failed for Lead=' + leadRec.Id + '. Error=' + e.getMessage());
                }
            }
        }
        if (!emailMessages.isEmpty()) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emailMessages, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for ( Messaging.SendEmailError err : results[i].getErrors()  ) {
                        System.debug( 'SSM email failed: ' + err.getMessage());
                    }
                } else {
                    System.debug('SSM email sent successfully.');
                }
            }
        }
    }
    public static void executeOpportunityAssignment(List<Opportunity> opportunities, String groupId) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }
        Assignment_Group__c assignmentGroup = [SELECT Id, Last_Allocated_RRid__c FROM Assignment_Group__c WHERE Id = :groupId LIMIT 1];
        List<Assignment_Group_Member__c> members = [SELECT Id,Assignment_Group__c,Assignment_Id__c,Group_Member__c,Active__c,Out_Of_Office__c,BreakTime_Started__c
            FROM Assignment_Group_Member__c WHERE Assignment_Group__c = :groupId AND Active__c = true AND Out_Of_Office__c = false AND BreakTime_Started__c = false ORDER BY Assignment_Id__c];
        if (members.isEmpty()) {
            return;
        }
        Integer lastRRId = assignmentGroup.Last_Allocated_RRid__c == null ? 0 : Integer.valueOf(String.valueOf(assignmentGroup.Last_Allocated_RRid__c));
        Integer memberIndex = 0;
        for (Integer i = 0; i < members.size(); i++) {
            Integer assignmentId = Integer.valueOf(
                String.valueOf( members[i].Assignment_Id__c));
            if (assignmentId > lastRRId) {
                memberIndex = i;
                break;
            }
        }
        for (Opportunity opp : opportunities) {
            if (opp.StageName != 'SPA Creation') {
                continue;
            }
            Assignment_Group_Member__c selectedMember = members[memberIndex];
            if (selectedMember.Group_Member__c == null) {
                continue;
            }
            Id csUserId = selectedMember.Group_Member__c;
            opp.OwnerId = csUserId;
            opp.CS_Member__c = csUserId;
            memberIndex++;
            if (memberIndex >= members.size()) {
                memberIndex = 0;
            }
            lastRRId = Integer.valueOf(String.valueOf(selectedMember.Assignment_Id__c));
        }
        assignmentGroup.Last_Allocated_RRid__c = lastRRId;
        update assignmentGroup;
        //update opportunities;
    }
}