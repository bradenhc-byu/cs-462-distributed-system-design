// Define the temperature component
angular.module('thresholdViolations').component('thresholdViolations', {
	templateUrl: 'threshold-violations/threshold-violation.component.html',
	controller: ['$http', '$interval', function thresholdViolationsController($http, $interval) {
		this.eci = "KKCc3MKtp13YPBbFjvhscR";
		this.violations = [];

		// These are the API URLs we need for this component
		var _this = this;
		var host = "http://localhost:8080/";
		var url = host + "sky/cloud/"+this.eci+"/temperature_store/threshold_violations";

		// Setup an interval function
		var thresholdViolations;
		this.getThresholdViolations = function(){
				$http.get(url).then(
					function success(response){
						_this.violations = [];
						for(i = 1; i < 10; i++){
							if(response.data.length - i < 0) break;
							_this.violations.push(response.data[response.data.length - i])
						}
					},
					function error(response){
						_this.violations = [];
						_this.violations.push({timestamp: "Fail", temperature: "Fail"})
				});		
		};

		thresholdViolations = $interval(this.getThresholdViolations, 3000);

		this.$onDestroy = function(){
			if(angular.isDefined(thresholdViolations)){
				$interval.cancel(thresholdViolations);
				thresholdViolations = undefined;
			}
		};

		// Initialize
		this.getThresholdViolations();
	}]
});