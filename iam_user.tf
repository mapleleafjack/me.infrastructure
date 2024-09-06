resource "aws_iam_user" "github_actions_user" {
  name = "github-actions-deploy"
}

resource "aws_iam_policy" "github_actions_policy" {
  name = "github-actions-deploy-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::me-frontend-bucket",
          "arn:aws:s3:::me-frontend-bucket/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "cloudfront:CreateInvalidation"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "github_actions_policy_attachment" {
  name       = "attach-github-actions-policy"
  users      = [aws_iam_user.github_actions_user.name]
  policy_arn = aws_iam_policy.github_actions_policy.arn
}
