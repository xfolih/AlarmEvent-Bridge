using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using MilestoneWebhookGui.Config;

namespace MilestoneWebhookGui
{
    public partial class CameraEditWindow
    {
        private readonly MilestoneData _data;
        private readonly CameraEntry? _existing;
        public CameraEntry? Result { get; private set; }

        private List<IdName> _allCameras = new();
        private List<IdName> _allEventTypes = new();
        private List<IoDisplay> _allIoList = new();

        public CameraEditWindow(MilestoneData data, CameraEntry? existing, string _)
        {
            InitializeComponent();
            _data = data;
            _existing = existing;
            _allCameras = _data.Cameras;
            _allEventTypes = _data.EventTypes;
            
            // Bara IO (inga användardefinierade händelser i IO-listan)
            foreach (var io in _data.IoList)
                _allIoList.Add(new IoDisplay { Id = io.Id, Display = $"[{io.Type}] {io.Name}" });
            
            CbCamera.ItemsSource = _allCameras;
            CbEventType.ItemsSource = _allEventTypes;
            CbIo.ItemsSource = _allIoList;
            CbAlarmActive.ItemsSource = _allEventTypes;
            CbAlarmInactive.ItemsSource = _allEventTypes;
            
            // Bestäm om det är IO eller användardefinierade händelser baserat på befintlig data
            bool useUserDefined = existing != null && 
                                 (!string.IsNullOrEmpty(existing.AlarmActiveEventTypeId) || 
                                  !string.IsNullOrEmpty(existing.AlarmInactiveEventTypeId));
            
            if (useUserDefined)
            {
                RbUserDefined.IsChecked = true;
            }
            else
            {
                RbIo.IsChecked = true;
            }
            
            // Uppdatera synlighet efter att alla kontroller är initierade
            this.Loaded += (s, e) => {
                if (RbIo.IsChecked == true)
                    RbIo_Checked(null, null);
                else if (RbUserDefined.IsChecked == true)
                    RbUserDefined_Checked(null, null);
            };
            
            if (existing != null)
            {
                CbCamera.SelectedValue = existing.CameraId;
                CbEventType.SelectedValue = existing.EventTypeId;
                CbIo.SelectedValue = existing.IoSourceId;
                CbAlarmActive.SelectedValue = existing.AlarmActiveEventTypeId;
                CbAlarmInactive.SelectedValue = existing.AlarmInactiveEventTypeId;
                TbWebhookUrl.Text = existing.WebhookUrl;
            }
        }
        
        private void RbIo_Checked(object? sender, RoutedEventArgs? e)
        {
            // Kontrollera att kontrollerna är initierade
            if (TbIoLabel == null || BorderIo == null || CbIo == null || 
                TbUserDefinedLabel == null || GridUserDefined == null)
                return;
            
            // Visa IO-val, dölj användardefinierade händelser
            TbIoLabel.Visibility = Visibility.Visible;
            BorderIo.Visibility = Visibility.Visible;
            CbIo.Visibility = Visibility.Visible;
            TbUserDefinedLabel.Visibility = Visibility.Collapsed;
            GridUserDefined.Visibility = Visibility.Collapsed;
        }
        
        private void RbUserDefined_Checked(object? sender, RoutedEventArgs e)
        {
            // Kontrollera att kontrollerna är initierade
            if (TbIoLabel == null || BorderIo == null || CbIo == null || 
                TbUserDefinedLabel == null || GridUserDefined == null)
                return;
            
            // Dölj IO-val, visa användardefinierade händelser
            TbIoLabel.Visibility = Visibility.Collapsed;
            BorderIo.Visibility = Visibility.Collapsed;
            CbIo.Visibility = Visibility.Collapsed;
            TbUserDefinedLabel.Visibility = Visibility.Visible;
            GridUserDefined.Visibility = Visibility.Visible;
        }

        private void FilterComboBox<T>(ComboBox comboBox, List<T> sourceList, string searchText, Func<T, string> getNameFunc)
        {
            if (comboBox == null || sourceList == null) return;
            if (string.IsNullOrWhiteSpace(searchText))
            {
                comboBox.ItemsSource = sourceList;
            }
            else
            {
                var searchLower = searchText.ToLowerInvariant();
                comboBox.ItemsSource = sourceList.Where(x => 
                    getNameFunc(x).ToLowerInvariant().Contains(searchLower)
                ).ToList();
            }
        }

        private void TbSearchCamera_TextChanged(object sender, TextChangedEventArgs e)
        {
            var textBox = sender as TextBox;
            FilterComboBox(CbCamera, _allCameras, textBox?.Text ?? "", x => x.Name);
        }

        private void TbSearchEventType_TextChanged(object sender, TextChangedEventArgs e)
        {
            var textBox = sender as TextBox;
            FilterComboBox(CbEventType, _allEventTypes, textBox?.Text ?? "", x => x.Name);
        }

        private void TbSearchIo_TextChanged(object sender, TextChangedEventArgs e)
        {
            var textBox = sender as TextBox;
            FilterComboBox(CbIo, _allIoList, textBox?.Text ?? "", x => x.Display);
        }

        private void TbSearchAlarmActive_TextChanged(object sender, TextChangedEventArgs e)
        {
            var textBox = sender as TextBox;
            FilterComboBox(CbAlarmActive, _allEventTypes, textBox?.Text ?? "", x => x.Name);
        }

        private void TbSearchAlarmInactive_TextChanged(object sender, TextChangedEventArgs e)
        {
            var textBox = sender as TextBox;
            FilterComboBox(CbAlarmInactive, _allEventTypes, textBox?.Text ?? "", x => x.Name);
        }

        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            var cam = CbCamera.SelectedItem as IdName;
            var ev = CbEventType.SelectedItem as IdName;
            var url = (TbWebhookUrl.Text ?? "").Trim();
            if (cam == null) { MessageBox.Show("V\u00e4lj en kamera."); return; }
            if (ev == null) { MessageBox.Show("V\u00e4lj en handelsetyp."); return; }
            if (string.IsNullOrEmpty(url)) { MessageBox.Show("Ange webhook-URL."); return; }
            
            string? ioSourceId = null;
            string? ioSourceName = null;
            string ioType = "output";
            string? alarmActiveEventTypeId = null;
            string? alarmInactiveEventTypeId = null;
            
            if (RbIo.IsChecked == true)
            {
                // Använd IO
                var io = CbIo.SelectedItem as IoDisplay;
                if (io == null) { MessageBox.Show("V\u00e4lj en ing\u00e5ng eller utg\u00e5ng."); return; }
                ioSourceId = io.Id;
                ioSourceName = io.Display;
                ioType = _data.IoList.FirstOrDefault(x => x.Id == io.Id)?.Type ?? "output";
            }
            else
            {
                // Använd användardefinierade händelser
                var alarmActive = CbAlarmActive.SelectedItem as IdName;
                var alarmInactive = CbAlarmInactive.SelectedItem as IdName;
                if (alarmActive == null || alarmInactive == null) 
                { 
                    MessageBox.Show("V\u00e4lj b\u00e5de 'Larm aktiv' och 'Larm inaktiv' h\u00e4ndelser."); 
                    return; 
                }
                alarmActiveEventTypeId = alarmActive.Id;
                alarmInactiveEventTypeId = alarmInactive.Id;
                ioType = "userDefined";
            }
            
            Result = new CameraEntry
            {
                CameraId = cam.Id,
                CameraName = cam.Name,
                EventTypeId = ev.Id,
                EventTypeName = ev.Name,
                IoSourceId = ioSourceId ?? "",
                IoSourceName = ioSourceName ?? "",
                IoType = ioType,
                AlarmActiveEventTypeId = alarmActiveEventTypeId,
                AlarmInactiveEventTypeId = alarmInactiveEventTypeId,
                WebhookUrl = url,
                Enabled = _existing?.Enabled ?? true
            };
            DialogResult = true;
            Close();
        }

        private void BtnCancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }

        private class IoDisplay
        {
            public string Id { get; set; } = "";
            public string Display { get; set; } = "";
        }
    }
}
