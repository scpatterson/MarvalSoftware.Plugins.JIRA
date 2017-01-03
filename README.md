
# JIRA Plugin for MSM

This plugin allows you to **Create**, **View**, **Link** and **Unlink** JIRA issues from within MSM. This is achieved by linking the MSM request number to a custom field that has already been configured within JIRA.

## Compatible Versions

| Plugin  | MSM         | JIRA     |
|---------|-------------|----------|
| 1.0.0   | 14.3.0.3085 | v7+      |

## Installation

Please see your MSM documentation for information on how to install plugins.

Once the plugin has been installed you will need to configure the following settings within the plugin page:

+ *JIRA Base URL* : The URL (including port) of your JIRA instance. `http://jira:8080 `
+ *JIRA Project* : The name of the project you wish to interact with. `MyProject`
+ *JIRA Custom Field ID* : The ID of the custom field within JIRA that contains the MSM request number. `CT_101_100`
+ *JIRA Custom Field Name* : The name of the custom field within JIRA that contains the MSM request number. `MSM Request Number`
+ *JIRA Username* : The username for authentication with JIRA.
+ *JIRA Password* : The password for authentication with JIRA.

We recommend that you create a new user within JIRA instead of re-using an existing account. This will allow you to revoke access should you want to. 

## Usage

The plugin can be launched from the quick menu after you load a request.

## Contributing

We welcome all feedback including feature requests and bug reports. Please raise these as issues on GitHub. If you would like to contribute to the project please fork the repository and issue a pull request.