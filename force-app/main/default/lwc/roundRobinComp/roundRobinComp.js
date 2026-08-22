import { LightningElement, api, track } from 'lwc';
import uId from '@salesforce/user/Id';
import timeBreak from '@salesforce/resourceUrl/TimeBreak';
import hourGlassPic from '@salesforce/resourceUrl/HourGlassPic';
import userCheckin from '@salesforce/apex/RoundRobinController.user_checkin';
import createUserTrackingRecord from '@salesforce/apex/RoundRobinController.createUserTrackingRecord';
import createUserAuditTrack from '@salesforce/apex/RoundRobinController.createUserAuditTrack';
import updateUserTrackingAudit from '@salesforce/apex/RoundRobinController.updateUserTrackingAudit';
import userCheckout from '@salesforce/apex/RoundRobinController.userCheckout';
import userFetchBreakTime from '@salesforce/apex/RoundRobinController.userFetchBreakTime';

export default class RoundRobinComp extends LightningElement {
    @api recordId;
    userId = uId;

    timeBreak = timeBreak;
    hourGlassPic = hourGlassPic;

    @track isCheckinDisabled = false;
    @track isCheckoutDisabled = true;
    @track isBreakinDisabled = true;
    @track isBreakoutDisabled = true;

    @track formattedTimer = '00:00:00';
    @track timerInterval;
    @track elapsedSeconds = 0;
    @track startTime;
    @track showBreakTimer = false;

    connectedCallback() {
        setTimeout(() => {
            this.onPageLoad();
        }, 2000);
    }

    onPageLoad() {
        debugger;
        userCheckin({ userId: this.userId })
            .then(result => {
                if (result === 'NoUserTrack') {
                    this.isCheckinDisabled = false;
                    this.isCheckoutDisabled = true;
                    this.isBreakinDisabled = true;
                    this.isBreakoutDisabled = true;
                } else if (result === 'userTrackAudit') {
                    this.isCheckinDisabled = true;
                    this.isCheckoutDisabled = false;
                    this.isBreakinDisabled = true;
                    this.isBreakoutDisabled = false;
                } else if (result === 'nouserTrackAudit') {
                    this.isCheckinDisabled = true;
                    this.isCheckoutDisabled = false;
                    this.isBreakinDisabled = false;
                    this.isBreakoutDisabled = true;
                } else if (result === 'userTrackAuditBreakIn') {
                    this.isCheckinDisabled = true;
                    this.isCheckoutDisabled = false;
                    this.isBreakinDisabled = true;
                    this.isBreakoutDisabled = false;
                } else if (result === 'checkOut') {
                    this.isCheckinDisabled = true;
                    this.isCheckoutDisabled = true;
                    this.isBreakinDisabled = true;
                    this.isBreakoutDisabled = true;
                }
                this.fetchBreakTime();
            })
            .catch(error => {
                console.error('Error in Apex method call: ', error);
            });
    }

    handleCheckin() {
        debugger;
        createUserTrackingRecord({ userId: this.userId })
            .then(result => {
                this.isCheckinDisabled = true;
                this.isCheckoutDisabled = false;
                this.isBreakinDisabled = false;
            })
            .catch(error => {
                console.error('Error creating user tracking record: ', error);
            });
    }

    handleBreakin() {
        debugger;
        createUserAuditTrack({ userId: this.userId, action: 'Break In' })
            .then(result => {
                this.isBreakinDisabled = true;
                this.isBreakoutDisabled = false;
                if (!this.timerInterval) {
                    this.startTimer();
                }
                this.showBreakTimer = true;
            })
            .catch(error => {
                console.error('Error creating user audit track: ', error);
            });
    }

    handleBreakout() {
        debugger;
        updateUserTrackingAudit({ userId: this.userId, action: 'Break Out' })
            .then(result => {
                this.isBreakinDisabled = false;
                this.isBreakoutDisabled = true;
                this.stopTimer();
            })
            .catch(error => {
                console.error('Error updating user tracking audit: ', error);
            });
    }

    startTimer() {
        debugger;
        this.startTime = Date.now() - this.elapsedSeconds * 1000;
        this.timerInterval = setInterval(() => {
            this.elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000);
            this.updateFormattedTimer();
        }, 1000);
    }

    stopTimer() {
        clearInterval(this.timerInterval);
        this.timerInterval = null;
    }

    updateFormattedTimer() {
        const hours = String(Math.floor(this.elapsedSeconds / 3600)).padStart(2, '0');
        const minutes = String(Math.floor((this.elapsedSeconds % 3600) / 60)).padStart(2, '0');
        const seconds = String(this.elapsedSeconds % 60).padStart(2, '0');
        this.formattedTimer = `${hours}:${minutes}:${seconds}`;
    }

    handleCheckout() {
        debugger;
        userCheckout({ userId: this.userId })
            .then(result => {
                if (result) {
                    this.isCheckinDisabled = true;
                    this.isCheckoutDisabled = true;
                    this.isBreakinDisabled = true;
                    this.isBreakoutDisabled = true;
                }
            })
            .catch(error => {
                console.error('Error in userCheckout Apex method:', error);
            });
    }

    fetchBreakTime() {
        debugger;
        userFetchBreakTime({ userId: this.userId })
            .then(result => {
                this.elapsedSeconds = result;
                this.showBreakTimer = this.elapsedSeconds !== 0;
                this.updateFormattedTimer();
            })
            .catch(error => {
                console.error('Error fetching break time:', error);
            });
    }
}