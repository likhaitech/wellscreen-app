
/**
 * WellScreen Firebase Cloud Functions
 *
 * Child device notifications for app time limits.
 */

exports.notifyChildAppTimeLimit =
  require('./child_app_time_limit_notifications').notifyChildAppTimeLimit;
