import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';

import LOGO_WHITE from '@salesforce/resourceUrl/Logo_White';
import getLeadDetails from '@salesforce/apex/ScheduleVisitController.getLeadDetails';
import getOpportunityDetails from '@salesforce/apex/ScheduleVisitController.getOpportunityDetails';

import VISIT_OBJECT from '@salesforce/schema/Visit__c';
import REQUIREMENT_TYPE_FIELD from '@salesforce/schema/Visit__c.Requirement_Type__c';

import createVisit from '@salesforce/apex/ScheduleVisitController.createVisit';
import updateVisitStatus from '@salesforce/apex/ScheduleVisitController.updateVisitStatus';
import getVisits from '@salesforce/apex/ScheduleVisitController.getVisits';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class ScheduleVisit extends LightningElement {

   // @api recordId;
  //  @api objectApiName;
    logoWhite = LOGO_WHITE;
    pageSize = 3;
    visitTime = '';
    visitDate = '';
    remarks = '';
    requirementType = '';
    projectId = '';
    isSaving = false;
    showVisitList = false;
    showCreateVisit = false;
    isRescheduling = false;
    parentVisitId = null;
    visits = [];
    allVisits = [];

    get hasRecords() {
            return this.allVisits.length > 0;
    }
    get pageTitle() {
        return this.isRescheduling ? 'Reschedule a Visit' : 'Schedule a Visit';
    }
    get visitButtonLabel() {
        return this.isRescheduling ? 'Reschedule Visit' : 'Create Visit';
    }

    requirementTypeOptions = [];

    @wire(getObjectInfo, {
        objectApiName: VISIT_OBJECT
    })
    visitObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$visitObjectInfo.data.defaultRecordTypeId',
        fieldApiName: REQUIREMENT_TYPE_FIELD
    })
    wiredRequirementTypes({ data, error }) {

        if (data) {
            this.requirementTypeOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        }

        if (error) {
            console.error( 'Requirement Type Picklist Error:', error );
        }
    }
    // connectedCallback() {
    //     this.loadVisits();
    // }
    _recordId;
    _objectApiName;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;

        if (value) {
            this.loadVisits();
            this.loadRecordDetails();
        }
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }

    set objectApiName(value) {
        this._objectApiName = value;

        if (value) {
            this.loadRecordDetails();
        }
    }
    loadRecordDetails() {
        if (!this.recordId || !this.objectApiName) {
            return;
        }

        console.log('==============================');
        console.log('Record Id ==> ', this.recordId);
        console.log('Object API Name ==> ', this.objectApiName);
        console.log('==============================');

        if (this.objectApiName === 'Lead') {
            this.loadLeadDetails();
        } else if (this.objectApiName === 'Opportunity') {
            this.loadOpportunityDetails();
        }
    }
    loadLeadDetails() {
        getLeadDetails({ leadId: this.recordId })
                .then(result => {
                    console.log('Lead Details ==> ', JSON.stringify(result));

                    if (result) {
                        this.requirementType = result.Unit_Type__c || '';
                        this.projectId = result.Project__c || '';

                        console.log('Requirement Type ==> ', this.requirementType);
                        console.log('Project Id ==> ', this.projectId);
                    }
                })
                .catch(error => {
                    console.error('Error loading Lead details:', error);
                });
    }
    loadOpportunityDetails() {
        if (!this.recordId) {
            return;
        }
        getOpportunityDetails({opportunityId: this.recordId}) 
        .then(result => {
            if (result) {
                this.projectId = result.Project__c;
                if (result.Unit__r) {
                    this.requirementType = result.Unit__r.Unit_Type__c;
                }
            }
        })
        .catch(error => {
            console.error('Error loading Opportunity details:', error);
        });
    }
    handleShowCreateVisit() {
        const upcomingVisit = this.allVisits.find( visit => visit.Status__c === 'Upcoming'|| !visit.Status__c);
        if (upcomingVisit) {
            this.showToast( 'Visit Already Scheduled',
                'An upcoming visit is already present. Please complete or cancel the existing visit before scheduling a new one.',
                'warning'
            );
            return;
        }

        this.showVisitList = false;
        this.showCreateVisit = true;
    }
    handlePageChanged(event) {
        console.log( 'Page changed ==> ', JSON.stringify(event.detail.recordToDisplay) );
        this.visits = event.detail.recordToDisplay;
    }

    handleVisitTimeChange(event) {
        this.visitTime = event.target.value;
    }
    handleVisitDateChange(event){
        this.visitDate = event.target.value;

    }

    handleRemarksChange(event) {
        this.remarks = event.target.value;
    }

    handleRequirementTypeChange(event) {
        this.requirementType = event.detail.value;
    }

    handleProjectChange(event) {
        this.projectId = event.detail.recordId;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    handleReschedule(event) {
        const visitId = event.currentTarget.dataset.id;
        const selectedVisit = this.allVisits.find(visit => visit.Id === visitId);
        if (!selectedVisit) {
            this.showToast(
                'Error',
                'Unable to find the selected Visit.',
                'error'
            );
            return;
        }

        console.log('Rescheduling Visit ==> ', JSON.stringify(selectedVisit) );
        this.parentVisitId = selectedVisit.Id;
        this.isRescheduling = true;

        this.visitDate = selectedVisit.Visit_Date__c || '';
        this.visitTime = selectedVisit.Visit_Time__c || '';
        this.remarks = selectedVisit.Remarks__c || '';
        this.requirementType = selectedVisit.Requirement_Type__c || '';
        this.projectId = selectedVisit.Project__c || '';
        this.showVisitList = false;
        this.showCreateVisit = true;
    }
    formatTime(timeValue) {
        if (timeValue === null || timeValue === undefined || timeValue === '') {
            return '';
        }
        const totalMinutes = Math.floor(Number(timeValue) / 60000);
        let hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        const period = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12;
        if (hours === 0) {
            hours = 12;
        }
        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')} ${period}`;
    }
    async loadVisits() {
        try {
            const data = await getVisits({
                recordId: this.recordId
            });

            console.log('Visits ==> ', JSON.stringify(data));

            this.allVisits = (data || []).map(visit => ({
                ...visit,
                ProjectName: visit.Project__r?.Name || '',
                VisitUrl: '/' + visit.Id,
                Visit_Time__c: this.formatTime(visit.Visit_Time__c),
                showActions:visit.Status__c === 'Upcoming' || !visit.Status__c
               // showReschedule: visit.Status__c === 'Upcoming' ||!visit.Status__c
            }));
            this.visits = this.allVisits;

            if (this.allVisits.length > 0) {
                this.showVisitList = true;
                this.showCreateVisit = false;
                setTimeout(() => {
                    const pagination =
                        this.template.querySelector('c-custom-pagination-comp');

                    if (pagination) {
                        pagination.setPagination(this.pageSize);
                    }
                }, 0);

            } else {
                this.showVisitList = false;
                this.showCreateVisit = true;
            }

        } catch (error) {
            console.error('Load Visits Error:', error);

            this.showToast(
                'Error',
                error?.body?.message ||
                error?.message ||
                'Unable to load Visits.',
                'error'
            );
        }
    }

    async handleCreateVisit() {
        if (!this.visitDate) {
            this.showToast('Error', 'Please select Visit Date.', 'error');
            return;
        }
        if (!this.visitTime) {
            this.showToast('Error', 'Please select Visit Time.', 'error');
            return;
        }
        if (!this.requirementType) {
            this.showToast('Error', 'Please select Requirement Type.', 'error');
            return;
        }
        if (!this.projectId) {
            this.showToast('Error', 'Please select Project.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            let leadId = null;
            let opportunityId = null;
            if (this.objectApiName === 'Lead') {
                leadId = this.recordId;
            } else if (this.objectApiName === 'Opportunity') {
                opportunityId = this.recordId;
            }
            console.log('Object ==> ', this.objectApiName);
            console.log('Lead Id ==> ', leadId);
            console.log('Opportunity Id ==> ', opportunityId);
            console.log('Parent Visit Id ==> ', this.parentVisitId);

            await createVisit({
                leadId: leadId,
                opportunityId: opportunityId,
                projectId: this.projectId,
                requirementType: this.requirementType,
                visitDate: this.visitDate,
                visitTime: this.visitTime,
                remarks: this.remarks,
                parentVisitId: this.parentVisitId
            });
            await notifyRecordUpdateAvailable([
                { recordId: this.recordId }
            ]);

            this.showToast(
                'Success',
                this.isRescheduling
                    ? 'Visit rescheduled successfully.'
                    : 'Visit created successfully.',
                'success'
            );

            this.isRescheduling = false;
            this.parentVisitId = null;

            this.dispatchEvent(
                new CloseActionScreenEvent()
            );

        } catch (error) {

            console.error('Create Visit Error:', error);

            this.showToast(
                'Error',
                error?.body?.message ||
                'Unable to create Visit.',
                'error'
            );

        } finally {
            this.isSaving = false;
        }
    }
    async updateVisitStatus(visitId, status) {
        try {
            await updateVisitStatus({
                visitId: visitId,
                status: status
            });
            await notifyRecordUpdateAvailable([
                { recordId: this.recordId }
            ]);
            this.visits = this.visits.map(visit => {
                if (visit.Id === visitId) {
                    return {
                        ...visit,
                        Status__c: status,
                        showActions: false
                    };
                }
                return visit;
            });

            this.allVisits = this.allVisits.map(visit => {
                if (visit.Id === visitId) {
                    return {
                        ...visit,
                        Status__c: status,
                        showActions: false
                    };
                }
                return visit;
            });
            this.showToast('Success',  `Visit marked as ${status}.`, 'success' );
        } catch (error) {
            console.error('Update Visit Status Error:', error);

            this.showToast(
                'Error',
                error?.body?.message ||
                error?.message ||
                'Unable to update Visit status.',
                'error'
            );
        }
    }
    async handleCompleted(event) {
        const visitId = event.currentTarget.dataset.id;

        await this.updateVisitStatus(visitId, 'Completed');
    }

    async handleCancelled(event) {
        const visitId = event.currentTarget.dataset.id;

        await this.updateVisitStatus(visitId, 'Cancelled');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}