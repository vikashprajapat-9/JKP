import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';

import LOGO_WHITE from '@salesforce/resourceUrl/Logo_White';

import VISIT_OBJECT from '@salesforce/schema/Visit__c';
import REQUIREMENT_TYPE_FIELD from '@salesforce/schema/Visit__c.Requirement_Type__c';

import createVisit from '@salesforce/apex/ScheduleVisitController.createVisit';
import updateVisitStatus from '@salesforce/apex/ScheduleVisitController.updateVisitStatus';
import getVisits from '@salesforce/apex/ScheduleVisitController.getVisits';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class ScheduleVisit extends LightningElement {

   // @api recordId;
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
    visits = [];
    allVisits = [];

    get hasRecords() {
            return this.allVisits.length > 0;
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

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;

        if (value) {
            this.loadVisits();
        }
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
                showActions:visit.Status__c === 'Upcoming' || !visit.Status__c
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
            this.showToast('Error','Please select Visit Time.','error');
            return;
        }

        if (!this.requirementType) {
            this.showToast('Error','Please select Requirement Type.','error'
            );
            return;
        }

        if (!this.projectId) {
            this.showToast('Error','Please select Project.','error');
            return;
        }

        this.isSaving = true;

        try {    
            console.log('Visit Date ==> ', this.visitDate);
            console.log('Visit Time ==> ',  this.visitTime);
             await createVisit({
                leadId: this.recordId,
                projectId: this.projectId,
                requirementType: this.requirementType,
                visitDate: this.visitDate,
                visitTime:  this.visitTime,
                remarks: this.remarks
            });
            await notifyRecordUpdateAvailable([
                { recordId: this.recordId }
            ]);
            this.showToast('Success','Visit created successfully.','success' );
            this.dispatchEvent(
                new CloseActionScreenEvent()
            );

        } catch (error) {
            console.error('Create Visit Error:',error  );
            this.showToast( 'Error',error?.body?.message ||
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