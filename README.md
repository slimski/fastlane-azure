A basic [Fastlane](https://fastlane.tools/) action that can upload to Azure blob storage. It's similar to the S3 action but not quite as full featured.

## Setup
You can import it using the import_from_git action:
```
import_from_git(
  url: 'https://github.com/slimski/fastlane-azure.git'  
)
```

## Usage
Your azure account name and access key can be configured as environmental variables or passed in. The ipa and dsym file will be automatically found if you're using the other Fastlane actions.

This example would upload to the "some_container" in your Azure account to "ios/<BUILD_NUMBER>/app.ipa"
```
azure(
  account_name: "my_azure_account",
  access_key: "my_secret_azure_key",
  container: "some_container",
  path: "ios/" + options[:build_number]
)
```
