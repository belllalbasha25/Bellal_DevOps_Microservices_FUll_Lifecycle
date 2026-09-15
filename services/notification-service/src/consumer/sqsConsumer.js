// Long-poll SQS consumer. Runs as part of the service process for simplicity.
// In a busier system you'd run this as a separate deployment.

const { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');
const handlers = require('../handlers');
const logger = require('../logger');

const QUEUE_URL = process.env.SQS_QUEUE_URL;
const REGION = process.env.AWS_REGION || 'us-east-1';

async function startSqsConsumer() {
  const client = new SQSClient({ region: REGION });
  logger.info({ queue: QUEUE_URL }, 'starting SQS consumer');

  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      const { Messages = [] } = await client.send(new ReceiveMessageCommand({
        QueueUrl: QUEUE_URL,
        MaxNumberOfMessages: 10,
        WaitTimeSeconds: 20,            // long-poll
        MessageAttributeNames: ['All'],
      }));

      for (const msg of Messages) {
        try {
          const event = JSON.parse(msg.Body);
          await handlers.handle(event);
          await client.send(new DeleteMessageCommand({
            QueueUrl: QUEUE_URL,
            ReceiptHandle: msg.ReceiptHandle,
          }));
        } catch (err) {
          // Don't delete — let visibility timeout expire and SQS redeliver.
          // After max retries it'll go to the DLQ (set up via console).
          logger.error({ err: err.message }, 'handler failed; message will redeliver');
        }
      }
    } catch (err) {
      logger.error({ err: err.message }, 'SQS poll error');
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

module.exports = { startSqsConsumer };

