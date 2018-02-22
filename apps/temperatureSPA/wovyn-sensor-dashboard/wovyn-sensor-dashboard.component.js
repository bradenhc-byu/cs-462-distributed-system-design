// Configure the component
angular.module('wovynSensorDashboard').component('wovynSensorDashboard', {
	templateUrl: 'wovyn-sensor-dashboard/wovyn-sensor-dashboard.component.html',
	controller: ['$http', function WovynSensorDashboardController($http){
		// Configure the ECI channel
		this.eci = "KKCc3MKtp13YPBbFjvhscR";

		// Setup data members
		this.profile = {
			name: "Wovyn TS",
			location: {latitude: 0, longitude: 0 },
			contact: "",
			threshold: 0
		};

		// Get a reference to the component
		var _cmpnt = this;
		
		// Define API URLs
		var host = "http://localhost:8080/";
		var profileUrl = host + "sky/cloud/"+this.eci+"/sensor_profile/profile";
		var saveUpdatesUrl = host + "sky/event/"+this.eci+"/27/sensor/profile_updated";

		// Setup function declarations
		this.initializeProfile = function(){
			$http.get(profileUrl).then(function success(response){
				_cmpnt.profile = response.data;
			},
			function error(response){
				alert("Failed to retrieve profile information");
			});
		}

		this.updateProfile = function(){
			var data = JSON.stringify(_cmpnt.profile);
			$http.post(saveUpdatesUrl, data, {headers: {'Content-Type': 'application/json'}}).then(
				function success(response){
					alert("Update success!");
				},
				function error(response){
					alert("Update failure");
				});
		}

		// Initialize member variables
		this.initializeProfile();
	}]
});