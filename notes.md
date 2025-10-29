# Notes

## Microsoft Graph API Requirements

* Permissions:
  * `LicenseAssignment.ReadWrite.All`
  * `Directory.Read.All`
  * `Mail.Send`
  * `Sites.Selected`
    * This requires manually giving the registered app "`FullControl`" permission to the SharePoint Online site.
    * The script for adding this permission is at `helper\add-app-site-permission.ps1`.

## SharePoint Online List

| Column Name    | Required | Type           | Unique Value | Indexed | Other Settings                            | Remarks                                                                                       |
| -------------- | -------- | -------------- | ------------ | ------- | ----------------------------------------- | --------------------------------------------------------------------------------------------- |
| Ticket         | True     | Text           | False        | True    |                                           | Ticket reference for this task.                                                               |
| Username       | True     | Text           | False        | False   |                                           | User's UPN (ie. <someone@domain.com>)                                                         |
| Due Date       | True     | Date           | False        | True    |                                           | Date when to remove license                                                                   |
| Status         | True     | Choice         | False        | True    | Choices: `Pending`,`Completed`,`Canceled` | Default: `Pending`                                                                            |
| Completed Date | False    | Date           | False        | False   |                                           | Date when the task is completed. This value is auto-updated. Don't modify the value manually. |
| Last Message   | False    | Text           | False        | False   |                                           | Auto-updated. Don't modify the value manually.                                                |
| Notes          | False    | Multiline Text | False        | False   | Append changes to existing text           | Auto-updated. Don't modify the value manually.                                                |

> NOTE: Column indexing is required so that Microsoft Graph can perform filtering against the list using those columns.
